import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';
import 'package:server_driven_ui/shql/parser/constants_set.dart';

class ShqlBindings {
  late ConstantsSet _constantsSet;
  late Runtime _runtime;
  final CancellationToken _cancellationToken = CancellationToken();

  final Map<String, List<VoidCallback>> _listeners = {};

  ShqlBindings({
    required this.onMutated,
    Function(dynamic value)? printLine,
    Future<String?> Function()? readline,
    Future<String?> Function(String prompt)? prompt,
    Future<void> Function(String routeName)? navigate,
    Future<dynamic> Function(String url)? fetch,
    Future<void> Function(String key, dynamic value)? saveState,
    Future<dynamic> Function(String key, dynamic defaultValue)? loadState,
  }) {
    _constantsSet = Runtime.prepareConstantsSet();
    _runtime = Runtime.prepareRuntime(_constantsSet);
    _runtime.printFunction = printLine;
    _runtime.readlineFunction = readline;
    _runtime.promptFunction = prompt;
    _runtime.navigateFunction = navigate;
    _runtime.fetchFunction = fetch;
    _runtime.saveStateFunction = saveState;
    _runtime.loadStateFunction = loadState;
    _runtime.notifyListeners = notifyListeners;
  }

  final VoidCallback onMutated;

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

  Future<dynamic> eval(String expr, {Map<String, dynamic>? boundValues}) async {
    try {
      return await Engine.execute(
        expr,
        runtime: _runtime,
        constantsSet: _constantsSet,
        cancellationToken: _cancellationToken,
        boundValues: boundValues,
      );
    } catch (e) {
      // Rethrow the exception to be handled by the FutureBuilder in the UI.
      rethrow;
    }
  }

  Future<dynamic> call(
    String code, {
    bool targeted = false,
    Map<String, dynamic>? boundValues,
  }) async {
    try {
      final result = await Engine.execute(
        code,
        runtime: _runtime,
        constantsSet: _constantsSet,
        cancellationToken: _cancellationToken,
        boundValues: boundValues,
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
