import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

import 'conflict_resolver_dialog.dart' show ReviewAction;

Widget _b(BuildContext c, Map<String, dynamic> node, String p) =>
    WidgetRegistry.buildStatic(c, node, 'dialog.$p');

/// Shows a text-input dialog over the current navigator overlay.
/// Uses the PromptDialog YAML screen with SHQL™ CLOSE_DIALOG directive.
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
/// Uses the YesNoDialog YAML screen with SHQL™ CLOSE_DIALOG directive.
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
/// Uses the ReconcileDialog YAML screen with SHQL™ CLOSE_DIALOG directive.
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

/// Shows a hero review dialog during search (Save / Skip / Save All / Cancel).
/// Displays hero image, name, alignment and total power.
Future<ReviewAction> showHeroReviewDialog(
  GlobalKey<NavigatorState> navigatorKey,
  dynamic hero,
  int current,
  int total,
) {
  final completer = Completer<ReviewAction>();
  if (hero is! HeroModel) {
    completer.complete(ReviewAction.cancel);
    return completer.future;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final overlayContext = navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      completer.complete(ReviewAction.cancel);
      return;
    }

    final ps = hero.powerStats;
    final totalPower = (ps.intelligence?.value ?? 0) + (ps.strength?.value ?? 0)
        + (ps.speed?.value ?? 0) + (ps.durability?.value ?? 0)
        + (ps.power?.value ?? 0) + (ps.combat?.value ?? 0);

    try {
      final result = await showDialog<ReviewAction>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('$current of $total'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hero.image.url != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    hero.image.url!,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, _) => const Icon(Icons.person, size: 80),
                  ),
                ),
              const SizedBox(height: 12),
              Text(hero.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Alignment: ${hero.biography.alignment.name}',
                style: TextStyle(color: Colors.grey[600])),
              Text('Total Power: $totalPower',
                style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.skip),
              child: const Text('Skip'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.saveAll),
              child: const Text('Save All'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ReviewAction.save),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      completer.complete(result ?? ReviewAction.cancel);
    } catch (e) {
      debugPrint('Review dialog error: $e');
      completer.complete(ReviewAction.cancel);
    }
  });

  return completer.future;
}
