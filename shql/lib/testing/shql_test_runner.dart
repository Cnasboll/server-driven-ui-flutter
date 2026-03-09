import 'dart:io';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parser.dart';

/// Execution strategy injected into [ShqlTestRunner].
///
/// [src] is the complete SHQL™ source to execute (may include a stdlib
/// prelude). [runtime] holds registered native callbacks. [cs] is the shared
/// constants set. [boundValues] are additional variables to inject before
/// execution.
typedef ShqlExecutorFn = Future<dynamic> Function(
  String src,
  Runtime runtime,
  ConstantsSet cs, {
  Map<String, dynamic>? boundValues,
});

/// Framework-agnostic SHQL™ test runner.
///
/// Assertion callbacks are injected so this class works with any Dart test
/// framework (`package:test`, `package:flutter_test`, or raw `assert`).
///
/// Usage:
/// ```dart
/// import 'package:test/test.dart';
/// import 'package:shql/testing/shql_test_runner.dart';
///
/// void main() {
///   late ShqlTestRunner h;
///   setUp(() async {
///     h = ShqlTestRunner.withExpect(expect);
///     await h.setUp();
///     await h.loadFile('assets/shql/navigation.shql');
///   });
///
///   test('GO_TO pushes route', () async {
///     await h.test(r"""
///       Nav.GO_TO('heroes');
///       ASSERT_CONTAINS(Nav.navigation_stack, 'heroes');
///     """);
///   });
/// }
/// ```
class ShqlTestRunner {
  /// Called for every assertion.
  /// [actual] is the evaluated value, [expected] is the target,
  /// [expr] is the SHQL expression text (for error messages).
  final void Function(dynamic actual, dynamic expected, String expr) onExpect;

  /// Custom execution strategy. When null the default [Engine.execute] is used.
  /// When provided, [test] prepends all accumulated prelude source and calls
  /// this function — enabling bytecode or any other execution backend.
  final ShqlExecutorFn? _executor;

  late Runtime runtime;
  late ConstantsSet constantsSet;

  /// SHQL™ source accumulated by [setUp] and [loadFile].
  /// Custom executors receive this as a prefix so they can recompile the full
  /// program (stdlib + loaded files + test code) in a single pass.
  final List<String> _sourcePrelude = [];

  /// Records every mocked function invocation as `"NAME(arg1, arg2)"`.
  final List<String> callLog = [];
  final Map<String, int> _callCounts = {};

  ShqlTestRunner({required this.onExpect, ShqlExecutorFn? executor})
      : _executor = executor;

  /// Convenience: wire to `expect()` from package:test or package:flutter_test.
  factory ShqlTestRunner.withExpect(
    void Function(dynamic actual, dynamic expected, {String? reason}) expect,
  ) {
    return ShqlTestRunner(
      onExpect: (actual, expected, expr) =>
          expect(actual, expected, reason: expr),
    );
  }

  /// Bytecode-backed variant.
  ///
  /// [setUp] and [loadFile] still execute via the tree-walking engine so that
  /// native Dart callbacks are registered on [runtime]. [test] then compiles
  /// the full accumulated prelude + test source as a single bytecode program
  /// and executes it on the bytecode VM — both modes share the same [runtime]
  /// so registered native callbacks are bridged automatically.
  factory ShqlTestRunner.bytecodeWithExpect(
    void Function(dynamic actual, dynamic expected, {String? reason}) expect,
  ) {
    return ShqlTestRunner(
      onExpect: (actual, expected, expr) =>
          expect(actual, expected, reason: expr),
      executor: _bytecodeExecutor,
    );
  }

  static Future<dynamic> _bytecodeExecutor(
    String src,
    Runtime runtime,
    ConstantsSet cs, {
    Map<String, dynamic>? boundValues,
  }) {
    final tree = Parser.parse(src, cs, sourceCode: src);
    final program = BytecodeCompiler.compile(tree, cs);
    final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
    return BytecodeInterpreter(decoded, runtime).executeScoped(
      'main',
      boundValues: boundValues,
    );
  }

  /// Initialise the runtime, load stdlib + shql_test, register callbacks.
  ///
  /// [stdlibPath] defaults to `assets/stdlib.shql` (from shql package root).
  /// [testLibPath] defaults to `assets/shql_test.shql`.
  Future<void> setUp({
    String stdlibPath = 'assets/stdlib.shql',
    String testLibPath = 'assets/shql_test.shql',
  }) async {
    constantsSet = Runtime.prepareConstantsSet();
    runtime = Runtime.prepareRuntime(constantsSet);

    // Load stdlib as prelude (engine-execute + accumulate for custom executors)
    await _loadPrelude(await File(stdlibPath).readAsString());

    // Register test callbacks before loading shql_test.shql
    _registerTestCallbacks();

    // Load test primitives as prelude
    await _loadPrelude(await File(testLibPath).readAsString());

    _registerPlatformNoOps();
  }

  /// Initialise the runtime and load only shql_test.shql (no stdlib).
  ///
  /// Use this for tests that don't need stdlib functions (LENGTH, STATS, etc.).
  Future<void> setUpTestOnly({
    String testLibPath = 'assets/shql_test.shql',
  }) async {
    constantsSet = Runtime.prepareConstantsSet();
    runtime = Runtime.prepareRuntime(constantsSet);
    _registerTestCallbacks();
    await _loadPrelude(await File(testLibPath).readAsString());
    _registerPlatformNoOps();
  }

  void _registerPlatformNoOps() {
    runtime.setBinaryFunction('SAVE_STATE', (ctx, caller, key, value) async {});
    runtime.setBinaryFunction('LOAD_STATE', (ctx, caller, key, defaultValue) async => defaultValue);
    runtime.setUnaryFunction('NAVIGATE', (ctx, caller, route) async {});
    runtime.setBinaryFunction('SET', (ctx, caller, name, value) {
      caller!.scope.setVariable(runtime.identifiers.include((name as String).toUpperCase()), value);
    });
    runtime.setUnaryFunction('PUBLISH', (ctx, caller, name) {});
    runtime.setUnaryFunction('DEBUG_LOG', (ctx, caller, msg) {});
    runtime.setUnaryFunction('FETCH', (ctx, caller, url) async => null);
    runtime.setBinaryFunction('POST', (ctx, caller, url, body) async => null);
    runtime.setBinaryFunction('PATCH', (ctx, caller, url, body) async => null);
    runtime.setBinaryFunction('FETCH_AUTH', (ctx, caller, url, token) async => null);
    runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, url, body, token) async => null);
  }

  // ─── Execution ─────────────────────────────────────────────────────

  /// Execute [code] via the engine and accumulate it as prelude source.
  ///
  /// Used by [setUp] and [loadFile]. Custom executors (e.g. bytecode) receive
  /// the full accumulated prelude on every [test] call so they can recompile
  /// the entire program in one pass.
  Future<void> _loadPrelude(String code) async {
    await Engine.execute(code, runtime: runtime, constantsSet: constantsSet);
    _sourcePrelude.add(code);
  }

  Future<dynamic> _exec(String code, {Map<String, dynamic>? boundValues}) {
    if (_executor == null) {
      return Engine.execute(
        code,
        runtime: runtime,
        constantsSet: constantsSet,
        boundValues: boundValues,
      );
    }
    final fullSrc = [..._sourcePrelude, code].join('\n');
    return _executor(fullSrc, runtime, constantsSet, boundValues: boundValues);
  }

  /// Execute SHQL™ code (may contain EXPECT/ASSERT calls).
  Future<dynamic> test(String code, {Map<String, dynamic>? boundValues}) =>
      _exec(code, boundValues: boundValues);

  /// Load and execute a `.shql` file (accumulated as prelude for custom executors).
  Future<void> loadFile(String path) async {
    await _loadPrelude(await File(path).readAsString());
  }

  // ─── Object helpers ────────────────────────────────────────────────

  /// Create a SHQL [Object] from a Dart map.
  Object makeObject(Map<String, dynamic> map) {
    final obj = Object();
    for (final entry in map.entries) {
      final id = constantsSet.identifiers.include(entry.key.toUpperCase());
      obj.setVariable(id, entry.value);
    }
    return obj;
  }

  /// Read a named field from a SHQL [Object].
  dynamic readField(dynamic obj, String field) {
    if (obj is! Object) return null;
    final id = constantsSet.identifiers.include(field.toUpperCase());
    final member = obj.resolveIdentifier(id);
    if (member is Variable) return member.value;
    return member;
  }

  // ─── Mock registration ────────────────────────────────────────────

  /// Register a mock unary Dart callback that logs its invocation.
  void mockUnary(String name, [dynamic Function(dynamic)? impl]) {
    runtime.setUnaryFunction(name, (ctx, caller, arg) {
      _logCall(name, [arg]);
      return impl?.call(arg);
    });
  }

  /// Register a mock binary Dart callback that logs its invocation.
  void mockBinary(String name,
      [dynamic Function(dynamic, dynamic)? impl]) {
    runtime.setBinaryFunction(name, (ctx, caller, a, b) {
      _logCall(name, [a, b]);
      return impl?.call(a, b);
    });
  }

  /// Register a mock ternary Dart callback that logs its invocation.
  void mockTernary(String name,
      [dynamic Function(dynamic, dynamic, dynamic)? impl]) {
    runtime.setTernaryFunction(name, (ctx, caller, a, b, c) {
      _logCall(name, [a, b, c]);
      return impl?.call(a, b, c);
    });
  }

  void _logCall(String name, List<dynamic> args) {
    callLog.add('$name(${args.map(_describe).join(', ')})');
    _callCounts[name] = (_callCounts[name] ?? 0) + 1;
  }

  // ─── Internals ────────────────────────────────────────────────────

  void _registerTestCallbacks() {
    // ctx/caller are nullable: the bytecode VM passes null for both (it has no
    // ExecutionContext). None of these callbacks use ctx or caller, so this is safe.

    // EXPECT(actual, expected) — direct value comparison.
    runtime.setBinaryFunction(
      '__EXPECT',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic actual,
          dynamic expected) {
        onExpect(actual, expected, 'EXPECT($actual, $expected)');
      },
    );

    // ASSERT(condition) — direct boolean check.
    runtime.setUnaryFunction(
      '__ASSERT',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic condition) {
        onExpect(condition, true, 'ASSERT($condition)');
      },
    );

    // ASSERT_FALSE(condition) — direct boolean check (negated).
    runtime.setUnaryFunction(
      '__ASSERT_FALSE',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic condition) {
        onExpect(condition, false, 'ASSERT_FALSE($condition)');
      },
    );

    // ASSERT_TRUE(condition, label) — direct boolean check with label.
    runtime.setBinaryFunction(
      '__ASSERT_TRUE',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic condition,
          dynamic label) {
        onExpect(condition, true, '$label');
      },
    );

    // ASSERT_CALLED("name") — check call log.
    runtime.setUnaryFunction(
      '__ASSERT_CALLED',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic name) {
        final found = callLog.any((entry) => entry.startsWith('$name('));
        onExpect(
            found, true, 'ASSERT_CALLED("$name") — not found in call log');
      },
    );

    // ASSERT_NOT_CALLED("name") — check call log (negative).
    runtime.setUnaryFunction(
      '__ASSERT_NOT_CALLED',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic name) {
        final found = callLog.any((entry) => entry.startsWith('$name('));
        onExpect(found, false,
            'ASSERT_NOT_CALLED("$name") — unexpectedly found in call log');
      },
    );

    // ASSERT_CALL_COUNT("name", n) — check exact invocation count.
    runtime.setBinaryFunction(
      '__ASSERT_CALL_COUNT',
      (ExecutionContext? ctx, ExecutionNode? caller, dynamic name,
          dynamic count) {
        final actual = _callCounts['$name'] ?? 0;
        onExpect(actual, count,
            'ASSERT_CALL_COUNT("$name", $count) — actual: $actual');
      },
    );

    // CLEAR_CALL_LOG() — reset tracking.
    runtime.setNullaryFunction(
      '__CLEAR_CALL_LOG',
      (ExecutionContext? ctx, ExecutionNode? caller) {
        callLog.clear();
        _callCounts.clear();
      },
    );
  }

  /// Describe a value for call-log readability.
  static String _describe(dynamic value) {
    if (value is Object) {
      for (final entry in value.variables.entries) {
        if (entry.value.value is String) return entry.value.value as String;
      }
      return '<object>';
    }
    return '$value';
  }
}
