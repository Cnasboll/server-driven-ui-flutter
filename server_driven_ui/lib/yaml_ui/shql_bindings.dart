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

  ShqlBindings({
    required this.onMutated,
    Function(dynamic value)? printLine,
    Future<String?> Function()? readline,
    Future<String?> Function(String prompt)? prompt,
    Future<void> Function(String routeName)? navigate,
  }) {
    _constantsSet = Runtime.prepareConstantsSet();
    _runtime = Runtime.prepareRuntime(_constantsSet);
    _runtime.printFunction = printLine;
    _runtime.readlineFunction = readline;
    _runtime.promptFunction = prompt;
    _runtime.navigateFunction = navigate;
  }

  final VoidCallback onMutated;

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

  Future<dynamic> eval(String expr) async {
    try {
      return await Engine.execute(
        expr,
        runtime: _runtime,
        constantsSet: _constantsSet,
        cancellationToken: _cancellationToken,
      );
    } catch (e) {
      // Rethrow the exception to be handled by the FutureBuilder in the UI.
      rethrow;
    }
  }

  Future<dynamic> call(String code) async {
    try {
      final result = await Engine.execute(
        code,
        runtime: _runtime,
        constantsSet: _constantsSet,
        cancellationToken: _cancellationToken,
      );

      // If the call was successful, assume a mutation occurred and notify listeners.
      onMutated();
      return result;
    } catch (e) {
      // Rethrow to allow the caller (e.g., event handler in a widget) to handle it.
      rethrow;
    }
  }
}

/// Tiny helpers for YAML DSL parsing:
bool isShqlRef(dynamic v) => v is String && v.startsWith('shql:');
String stripPrefix(String s) => s.substring(s.indexOf(':') + 1).trim();
