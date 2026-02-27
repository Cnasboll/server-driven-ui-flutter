import 'dart:async';

import 'package:flutter/material.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

import 'conflict_resolver_dialog.dart' show ReviewAction;

Widget _b(BuildContext c, Map<String, dynamic> node, String p) =>
    WidgetRegistry.buildStatic(c, node, 'dialog.$p');

/// Shows a text-input dialog over the current navigator overlay.
/// Uses the PromptDialog YAML template with SHQL™ CLOSE_DIALOG directive.
Future<String> showPromptDialog(
  GlobalKey<NavigatorState> navigatorKey,
  GlobalKey<ScaffoldMessengerState> messengerKey,
  String prompt, [
  String defaultValue = '',
]) {
  final completer = Completer<String>();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final overlayContext = navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: _b(messengerKey.currentContext!, {
          'type': 'Text', 'props': {'data': 'Please configure your API key in Settings'},
        }, 'snack')),
      );
      completer.complete(defaultValue);
      return;
    }

    // Initialize SHQL™ variable for the TextField's current value
    WidgetRegistry.staticShql.setVariable('_DIALOG_TEXT', defaultValue);

    try {
      final result = await showDialog<dynamic>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => _b(ctx, {'type': 'PromptDialog', 'props': {
          'prompt': prompt,
          'defaultValue': defaultValue,
        }}, 'prompt') as AlertDialog,
      );
      completer.complete(result is String ? result : defaultValue);
    } catch (e) {
      debugPrint('Dialog error: $e');
      completer.complete(defaultValue);
    }
  });

  return completer.future;
}

/// Shows a yes/no confirmation dialog.
/// Uses the YesNoDialog YAML template with SHQL™ CLOSE_DIALOG directive.
Future<bool> showYesNoDialog(
  GlobalKey<NavigatorState> navigatorKey,
  String prompt,
) {
  final completer = Completer<bool>();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final overlayContext = navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      completer.complete(false);
      return;
    }

    try {
      final result = await showDialog<dynamic>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => _b(ctx, {'type': 'YesNoDialog', 'props': {
          'prompt': prompt,
        }}, 'yesno') as AlertDialog,
      );
      completer.complete(result == true);
    } catch (e) {
      debugPrint('Dialog error: $e');
      completer.complete(false);
    }
  });

  return completer.future;
}

/// Shows a reconcile action dialog (Accept / Skip / Accept All / Abort).
/// Uses the ReconcileDialog YAML template with SHQL™ CLOSE_DIALOG directive.
Future<ReviewAction> showReconcileDialog(
  GlobalKey<NavigatorState> navigatorKey,
  String prompt,
) {
  final completer = Completer<ReviewAction>();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final overlayContext = navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      completer.complete(ReviewAction.cancel);
      return;
    }

    try {
      final result = await showDialog<dynamic>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => _b(ctx, {'type': 'ReconcileDialog', 'props': {
          'prompt': prompt,
        }}, 'reconcile') as AlertDialog,
      );
      // CLOSE_DIALOG returns string values — map to enum
      completer.complete(switch (result) {
        'save' => ReviewAction.save,
        'skip' => ReviewAction.skip,
        'saveAll' => ReviewAction.saveAll,
        _ => ReviewAction.cancel,
      });
    } catch (e) {
      debugPrint('Reconcile dialog error: $e');
      completer.complete(ReviewAction.cancel);
    }
  });

  return completer.future;
}
