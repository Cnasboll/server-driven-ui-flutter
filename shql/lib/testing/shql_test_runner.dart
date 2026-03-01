import 'dart:io';

import 'package:shql/engine/engine.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';

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
///   test('navigation', () async {
///     final r = ShqlTestRunner.withExpect(expect);
///     await r.setUp();
///     await r.loadFile('assets/shql/navigation.shql');
///     await r.eval(r"""
///       Nav.GO_TO('heroes');
///       EXPECT("Nav.navigation_stack[LENGTH(Nav.navigation_stack) - 1]", 'heroes');
///     """);
///   });
/// }
/// ```
class ShqlTestRunner {
  /// Called for every assertion.
  /// [actual] is the evaluated value, [expected] is the target,
  /// [expr] is the SHQL expression text (for error messages).
  final void Function(dynamic actual, dynamic expected, String expr) onExpect;

  late Runtime runtime;
  late ConstantsSet constantsSet;

  /// Records every mocked function invocation as `"NAME(arg1, arg2)"`.
  final List<String> callLog = [];
  final Map<String, int> _callCounts = {};

  ShqlTestRunner({required this.onExpect});

  /// Convenience: wire to `expect()` from package:test or package:flutter_test.
  factory ShqlTestRunner.withExpect(
    void Function(dynamic actual, dynamic expected, {String? reason}) expect,
  ) {
    return ShqlTestRunner(
      onExpect: (actual, expected, expr) =>
          expect(actual, expected, reason: expr),
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

    // Load stdlib
    await _exec(await File(stdlibPath).readAsString());

    // Register test callbacks before loading shql_test.shql
    _registerTestCallbacks();

    // Load test primitives
    await _exec(await File(testLibPath).readAsString());

    // Wire runtime callbacks with no-op defaults
    runtime.saveStateFunction = (key, value) async {};
    runtime.loadStateFunction = (key, defaultValue) async => defaultValue;
    runtime.navigateFunction = (route) async {};
    runtime.notifyListeners = (name) {};
    runtime.debugLogFunction = (msg) {};
  }

  // ─── Execution ─────────────────────────────────────────────────────

  Future<dynamic> _exec(String code, {Map<String, dynamic>? boundValues}) {
    return Engine.execute(
      code,
      runtime: runtime,
      constantsSet: constantsSet,
      boundValues: boundValues,
    );
  }

  /// Execute SHQL code (may contain EXPECT/ASSERT calls).
  Future<dynamic> eval(String expr, {Map<String, dynamic>? boundValues}) =>
      _exec(expr, boundValues: boundValues);

  /// Load and execute a `.shql` file.
  Future<void> loadFile(String path) async {
    await _exec(await File(path).readAsString());
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
    // EXPECT(actual, expected) — direct value comparison.
    runtime.setBinaryFunction(
      '__EXPECT',
      (ExecutionContext ctx, ExecutionNode caller, dynamic actual,
          dynamic expected) {
        onExpect(actual, expected, 'EXPECT($actual, $expected)');
      },
    );

    // ASSERT(condition) — direct boolean check.
    runtime.setUnaryFunction(
      '__ASSERT',
      (ExecutionContext ctx, ExecutionNode caller, dynamic condition) {
        onExpect(condition, true, 'ASSERT($condition)');
      },
    );

    // ASSERT_FALSE(condition) — direct boolean check (negated).
    runtime.setUnaryFunction(
      '__ASSERT_FALSE',
      (ExecutionContext ctx, ExecutionNode caller, dynamic condition) {
        onExpect(condition, false, 'ASSERT_FALSE($condition)');
      },
    );

    // ASSERT_TRUE(condition, label) — direct boolean check with label.
    runtime.setBinaryFunction(
      '__ASSERT_TRUE',
      (ExecutionContext ctx, ExecutionNode caller, dynamic condition,
          dynamic label) {
        onExpect(condition, true, '$label');
      },
    );

    // ASSERT_CALLED("name") — check call log.
    runtime.setUnaryFunction(
      '__ASSERT_CALLED',
      (ExecutionContext ctx, ExecutionNode caller, dynamic name) {
        final found = callLog.any((entry) => entry.startsWith('$name('));
        onExpect(
            found, true, 'ASSERT_CALLED("$name") — not found in call log');
      },
    );

    // ASSERT_NOT_CALLED("name") — check call log (negative).
    runtime.setUnaryFunction(
      '__ASSERT_NOT_CALLED',
      (ExecutionContext ctx, ExecutionNode caller, dynamic name) {
        final found = callLog.any((entry) => entry.startsWith('$name('));
        onExpect(found, false,
            'ASSERT_NOT_CALLED("$name") — unexpectedly found in call log');
      },
    );

    // ASSERT_CALL_COUNT("name", n) — check exact invocation count.
    runtime.setBinaryFunction(
      '__ASSERT_CALL_COUNT',
      (ExecutionContext ctx, ExecutionNode caller, dynamic name,
          dynamic count) {
        final actual = _callCounts['$name'] ?? 0;
        onExpect(actual, count,
            'ASSERT_CALL_COUNT("$name", $count) — actual: $actual');
      },
    );

    // CLEAR_CALL_LOG() — reset tracking.
    runtime.setNullaryFunction(
      '__CLEAR_CALL_LOG',
      (ExecutionContext ctx, ExecutionNode caller) {
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
