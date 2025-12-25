import 'dart:async';

import 'package:flutter/material.dart';

import 'conflict_resolver_dialog.dart' show ReviewAction;

/// Shows a text-input dialog over the current navigator overlay.
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
        const SnackBar(content: Text('Please configure your API key in Settings')),
      );
      completer.complete(defaultValue);
      return;
    }

    final controller = TextEditingController(text: defaultValue);
    try {
      final result = await showDialog<String>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Configuration Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(prompt),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(defaultValue),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      completer.complete(result ?? defaultValue);
    } catch (e) {
      debugPrint('Dialog error: $e');
      completer.complete(defaultValue);
    }
  });

  return completer.future;
}

/// Shows a yes/no confirmation dialog.
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
      final result = await showDialog<bool>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Text(prompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      completer.complete(result ?? false);
    } catch (e) {
      debugPrint('Dialog error: $e');
      completer.complete(false);
    }
  });

  return completer.future;
}

/// Shows a reconcile action dialog (Accept / Skip / Accept All / Abort).
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
      final result = await showDialog<ReviewAction>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Reconcile'),
          content: Text(prompt),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.cancel),
              child: const Text('Abort'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.skip),
              child: const Text('Skip'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.saveAll),
              child: const Text('Accept All'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.save),
              child: const Text('Accept'),
            ),
          ],
        ),
      );
      completer.complete(result ?? ReviewAction.cancel);
    } catch (e) {
      debugPrint('Reconcile dialog error: $e');
      completer.complete(ReviewAction.cancel);
    }
  });

  return completer.future;
}
