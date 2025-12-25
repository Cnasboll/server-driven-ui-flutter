import 'package:flutter/widgets.dart';
import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';
import 'package:server_driven_ui/shql/parser/constants_set.dart';

/// Wraps your SHQL runtime and exposes:
/// - expr: <code>
/// - call: <code>
class ShqlBindings {
  late ConstantsSet _constantsSet;
  late Runtime _runtime; // <-- replace with your Runtime type
  final VoidCallback onMutated;
  final CancellationToken _cancellationToken = CancellationToken();

  ShqlBindings({
    required this.onMutated,
    required Function(dynamic value) printLine,
    required Future<String?> Function() readline,
    required Future<String?> Function(String prompt) prompt,
  }) {
    _constantsSet = Runtime.prepareConstantsSet();
    _runtime = Runtime.prepareRuntime(_constantsSet);
    _runtime.printFunction = printLine;
    _runtime.readlineFunction = readline;
    _runtime.promptFunction = prompt;
  }

  Future<void> loadProgram(
    String programText,
    String loading,
    String success,
    String failure,
  ) async {
    _runtime.printFunction?.call(loading);
    _runtime.printFunction?.call(programText);
    await Engine.execute(
          programText,
          runtime: _runtime,
          constantsSet: _constantsSet,
          cancellationToken: _cancellationToken,
        )
        .then((value) {
          _runtime.printFunction?.call(success);
        })
        .catchError((error, stackTrace) {
          _runtime.printFunction?.call('$failure\n$error');
        });
  }

  /// Evaluate expression for binding.
  Future<dynamic> eval(String expr) async {
    return await Engine.evalExpr(
      expr,
      runtime: _runtime,
      constantsSet: _constantsSet,
    );
  }

  /// Execute statement/procedure for events. Triggers rebuild after success.
  Future<dynamic> call(String code) async {
    final res = await await Engine.execute(
      code,
      runtime: _runtime,
      constantsSet: _constantsSet,
      cancellationToken: _cancellationToken,
    );
    onMutated();
    return res;
  }
}

/// Tiny helpers for YAML DSL parsing:
bool isExprRef(dynamic v) => v is String && v.startsWith('expr:');
bool isCallRef(dynamic v) => v is String && v.startsWith('call:');
String stripPrefix(String s) => s.substring(s.indexOf(':') + 1).trim();
