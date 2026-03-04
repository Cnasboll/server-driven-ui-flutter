import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parse_tree.dart';
import 'package:shql/parser/parser.dart';
import 'package:yaml/yaml.dart';

/// The SHQL™ execution context for a node in a YAML-rendered widget tree.
///
/// Created by [ShqlBindings.createScreenContext] for the root screen; every
/// registered YAML widget then receives a new context wrapping the same [scope]
/// but pointing to its own [map] node in the widget tree.
///
/// [scope] — a SHQL™ [Scope] child of globalScope, shared by the entire
/// widget tree for one screen.  Callbacks pass it as `startingScope` to
/// [ShqlBindings.eval] / [ShqlBindings.call].
///
/// [map] — a plain Dart [Map] representing *this* widget node.  The root map
/// is stored as `_SCREEN` in [scope]; child widget maps are attached under
/// their key in the parent map.
///
/// [parent] — the immediate parent node's map (`null` at the screen root).
/// Exposed as `_PARENT` alongside `_SELF` in bound variables when SHQL
/// callbacks execute — it is never stored inside [map].
class ScreenContext {
  final dynamic scope;
  final Map<String, dynamic> map;
  final Map<String, dynamic>? parent;

  const ScreenContext(this.scope, this.map, {this.parent});
}

class ShqlBindings {
  late ConstantsSet _constantsSet;
  late Runtime _runtime;
  final CancellationToken _cancellationToken = CancellationToken();

  final Map<String, List<VoidCallback>> _listeners = {};

  ShqlBindings({
    required this.onMutated,
    ConstantsSet? constantsSet,
    Function(dynamic value)? printLine,
    Future<String?> Function()? readline,
    Future<String?> Function(String prompt)? prompt,
    Future<void> Function(String routeName)? navigate,
    Future<dynamic> Function(String url)? fetch,
    Future<dynamic> Function(String url, dynamic body)? post,
    Future<dynamic> Function(String url, dynamic body)? patch,
    Future<dynamic> Function(String url, String token)? fetchAuth,
    Future<dynamic> Function(String url, dynamic body, String token)? patchAuth,
    Future<void> Function(String key, dynamic value)? saveState,
    Future<dynamic> Function(String key, dynamic defaultValue)? loadState,
    Function(String message)? debugLog,
    Map<String, Function()>? nullaryFunctions,
    Map<String, Function(dynamic)>? unaryFunctions,
    Map<String, Function(dynamic, dynamic)>? binaryFunctions,
    Map<String, Function(dynamic, dynamic, dynamic)>? ternaryFunctions,
    Runtime? runtime,
  }) {
    _constantsSet = constantsSet ?? Runtime.prepareConstantsSet();
    _runtime = runtime ?? Runtime.prepareRuntime(_constantsSet);
    _runtime.printFunction = printLine;
    _runtime.readlineFunction = readline;
    _runtime.promptFunction = prompt;
    _runtime.navigateFunction = navigate;
    _runtime.fetchFunction = fetch;
    _runtime.postFunction = post;
    _runtime.patchFunction = patch;
    _runtime.fetchAuthFunction = fetchAuth;
    _runtime.patchAuthFunction = patchAuth;
    _runtime.saveStateFunction = saveState;
    _runtime.loadStateFunction = loadState;
    _runtime.debugLogFunction = debugLog;
    _runtime.notifyListeners = notifyListeners;

    if (nullaryFunctions != null) {
      for (final entry in nullaryFunctions.entries) {
        _runtime.setNullaryFunction(
          entry.key,
          (executionContext, caller) => entry.value(),
        );
      }
    }
    if (unaryFunctions != null) {
      for (final entry in unaryFunctions.entries) {
        _runtime.setUnaryFunction(
          entry.key,
          (executionContext, caller, arg) => entry.value(arg),
        );
      }
    }
    if (binaryFunctions != null) {
      for (final entry in binaryFunctions.entries) {
        _runtime.setBinaryFunction(
          entry.key,
          (executionContext, caller, p1, p2) => entry.value(p1, p2),
        );
      }
    }
    if (ternaryFunctions != null) {
      for (final entry in ternaryFunctions.entries) {
        _runtime.setTernaryFunction(
          entry.key,
          (executionContext, caller, p1, p2, p3) => entry.value(p1, p2, p3),
        );
      }
    }

    // Framework directive: CLOSE_DIALOG(value) — returns a sentinel map
    // that callShql intercepts to call Navigator.of(context).pop(value).
    _runtime.setUnaryFunction(
      'CLOSE_DIALOG',
      (executionContext, caller, value) =>
          <String, dynamic>{'__close_dialog__': true, 'value': value},
    );
  }

  final VoidCallback onMutated;

  Runtime get runtime => _runtime;
  ConstantsSet get constantsSet => _constantsSet;
  ConstantsTable<String> get identifiers => _runtime.identifiers;

  // ---------------------------------------------------------------------------
  // YAML screen local scope
  // ---------------------------------------------------------------------------
  //
  // When a YAML screen is rendered, [createScreenContext] creates one flat
  // SHQL™ Scope rooted at globalScope and pre-populated with the screen's
  // props as direct variables.  The [ScreenContext] is injected into every
  // child factory via the `screenCtx` parameter of [ChildBuilder] /
  // [WidgetFactory], exactly as ExecutionContext flows through execution nodes.
  // Callbacks close over the context and pass its scope as `startingScope`
  // when invoking [eval] or [call].
  //
  // One screen = one scope.  Widget namespacing is done via SHQL™ Objects
  // stored inside that scope, not by chaining child contexts.

  /// Create a [ScreenContext] for a YAML screen about to render.
  ///
  /// Each entry in [props] becomes a direct variable in the new SHQL™ scope
  /// (accessible as e.g. `LABEL`, not `__scope.LABEL`).
  ///
  /// Every screen gets exactly one flat scope rooted at [Runtime.globalScope].
  /// A root map (`_SCREEN`) is stored in the scope as the top of the widget
  /// tree; registered child widgets attach their own maps under it.
  ScreenContext createScreenContext(Map<String, dynamic> props) {
    final scope = Scope(Object(), constants: _runtime.globalScope.constants, parent: _runtime.globalScope);
    final screenMap = <String, dynamic>{};
    for (final entry in props.entries) {
      scope.members.setVariable(
        _runtime.identifiers.include(entry.key.toUpperCase()),
        entry.value,
      );
    }
    scope.members.setVariable(_runtime.identifiers.include('_SCREEN'), screenMap);
    return ScreenContext(scope, screenMap);
  }

  dynamic getVariable(String name) {
    var id = _constantsSet.identifiers.include(name.toUpperCase());
    var member = _runtime.globalScope.resolveIdentifier(id);
    var (value, _, _) = member;
    if (value is Variable) return value.value;
    return value;
  }

  void setVariable(String name, dynamic value) {
    var id = _constantsSet.identifiers.include(name.toUpperCase());
    _runtime.globalScope.members.setVariable(id, value);
  }

  /// Whether [value] is an SHQL™ Object (as opposed to a Dart Map or primitive).
  bool isShqlObject(dynamic value) => value is Object;

  /// Convert an SHQL™ [Object] to a `Map<String, dynamic>`.
  /// Only includes variable members (not user functions or self-references).
  Map<String, dynamic> objectToMap(dynamic obj) {
    if (obj is! Object) return {};
    final map = <String, dynamic>{};
    for (final entry in obj.variables.entries) {
      final name = _constantsSet.identifiers.constants[entry.key];
      final value = entry.value.value;
      // Skip THIS self-reference (injected by ObjectLiteralNode) to avoid
      // circular references when serializing.
      if (value is Object && identical(value, obj)) continue;
      map[name.toLowerCase()] = value;
    }
    return map;
  }

  /// Create an SHQL™ [Object] from a `Map<String, dynamic>`.
  Object mapToObject(Map<String, dynamic> map) {
    final obj = Object();
    for (final entry in map.entries) {
      final id = _constantsSet.identifiers.include(entry.key.toUpperCase());
      obj.setVariable(id, entry.value);
    }
    return obj;
  }

  void addListener(String key, VoidCallback listener) {
    _listeners.putIfAbsent(key, () => []).add(listener);
  }

  void removeListener(String key, VoidCallback listener) {
    _listeners[key]?.remove(listener);
  }

  void notifyListeners(String key) {
    final a = _listeners[key] ?? [];
    final b = _listeners['*'] ?? [];
    for (final listener in [...a, ...b]) {
      listener();
    }
  }

  Future<void> loadProgram(String programText, {String? name}) async {
    if (name != null) {
      _runtime.printFunction?.call('Loading $name ...');
    }
    _runtime.printFunction?.call(programText);

    await Engine.execute(
          programText,
          constantsSet: _constantsSet,
          runtime: _runtime,
          cancellationToken: _cancellationToken,
        )
        .then((_) {
          if (name != null) {
            _runtime.printFunction?.call('Finished loading $name.');
          }
        })
        .catchError((e) {
          if (name != null) {
            _runtime.printFunction?.call(
              'Failed to load $name: ${e.toString()}.',
            );
          }
          throw e;
        });
  }

  /// Parse an SHQL™ expression into a reusable [ParseTree].
  /// Use with [evalParsed] to avoid re-parsing in hot loops.
  ParseTree parse(String expr) => Parser.parse(expr, _constantsSet, sourceCode: expr);

  Future<dynamic> eval(String expr, {Map<String, dynamic>? boundValues, dynamic startingScope}) async {
    try {
      return await Engine.execute(
        expr,
        runtime: _runtime,
        constantsSet: _constantsSet,
        cancellationToken: _cancellationToken,
        boundValues: boundValues,
        startingScope: startingScope as Scope?,
      );
    } catch (e) {
      // Rethrow the exception to be handled by the FutureBuilder in the UI.
      rethrow;
    }
  }

  /// Execute a pre-parsed [ParseTree], skipping the parse step.
  Future<dynamic> evalParsed(ParseTree tree, {Map<String, dynamic>? boundValues, dynamic startingScope}) async {
    return await Engine.executeParsed(
      tree,
      runtime: _runtime,
      cancellationToken: _cancellationToken,
      boundValues: boundValues,
      startingScope: startingScope as Scope?,
    );
  }

  Future<dynamic> call(
    String code, {
    bool targeted = false,
    Map<String, dynamic>? boundValues,
    dynamic startingScope,
  }) async {
    try {
      // Strip `shql:` prefix if present (YAML DSL values may include it)
      final parsed = parseShql(code);
      final result = await Engine.execute(
        parsed.code.isNotEmpty ? parsed.code : code,
        runtime: _runtime,
        constantsSet: _constantsSet,
        cancellationToken: _cancellationToken,
        boundValues: boundValues,
        startingScope: startingScope as Scope?,
      );

      // If the call was successful and not a targeted update,
      // assume a general mutation occurred and rebuild the whole UI.
      if (!targeted) {
        onMutated();
      }
      return result;
    } catch (e) {
      // Rethrow to allow the caller (e.g., event handler in a widget) to handle it.
      rethrow;
    }
  }
}

/// Tiny helpers for YAML DSL parsing:
bool isShqlRef(dynamic v) => v is String && v.startsWith('shql');

/// Whether [key] is a callback property name (on* with uppercase third char).
/// Same heuristic used by [WidgetRegistry.substituteProps] and
/// [YamlUiEngine._resolveNode].
bool _isCallbackKey(String key) =>
    key.length > 2 && key.startsWith('on') && key[2] == key[2].toUpperCase();

/// Extract ALL SHQL™ expressions from a YAML string, in document order.
///
/// Walks the parsed YAML tree using [isShqlRef] and [parseShql] — the same
/// functions used at runtime — plus the `on*` callback key heuristic from
/// [WidgetRegistry.substituteProps].
///
/// Returns the raw SHQL™ code strings (without the `shql:` prefix).
List<String> extractShqlExpressions(String yamlContent) {
  final data = loadYaml(yamlContent);
  final exprs = <String>[];
  _collectShql(data, exprs, null);
  return exprs;
}

void _collectShql(dynamic node, List<String> out, String? parentKey) {
  if (node is String) {
    if (isShqlRef(node)) {
      final code = parseShql(node).code;
      if (code.isNotEmpty) out.add(code);
    } else if (parentKey != null &&
        _isCallbackKey(parentKey) &&
        !node.startsWith('prop:')) {
      // Bare SHQL™ on callback keys — same as substituteProps auto-prefix
      out.add(node);
    }
    return;
  }
  if (node is Map) {
    for (final entry in node.entries) {
      _collectShql(entry.value, out, entry.key as String?);
    }
    return;
  }
  if (node is List) {
    for (final item in node) {
      _collectShql(item, out, parentKey);
    }
  }
}

typedef ShqlParseResult = ({String code, bool targeted});

ShqlParseResult parseShql(String ref) {
  if (!isShqlRef(ref)) {
    return (code: ref, targeted: false);
  }

  final match = RegExp(
    r'^shql(\(targeted:\s*(true)\))?:\s*(.*)',
    dotAll: true,
  ).firstMatch(ref);

  if (match != null) {
    final isTargeted = match.group(2) == 'true';
    final code = match.group(3) ?? '';
    return (code: code.trim(), targeted: isTargeted);
  }

  // Fallback for old syntax, just in case
  final parts = ref.split(':');
  if (parts.length > 1) {
    return (code: parts.sublist(1).join(':').trim(), targeted: false);
  }

  return (code: '', targeted: false);
}
