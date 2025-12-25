import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hero_common/value_types/conflict_resolver.dart';
import 'package:hero_common/value_types/value_type.dart';

/// Actions for the one-by-one hero review dialog.
enum ReviewAction { save, skip, saveAll, cancel }

/// Shows a height/weight conflict resolution dialog.
/// Returns the chosen system of units and whether to apply to all, or null if cancelled.
Future<({SystemOfUnits? choice, bool applyToAll})?> showConflictDialog<T extends ValueType<T>>(
  GlobalKey<NavigatorState> navigatorKey,
  String valueTypeName,
  T value,
  T conflictingValue,
) {
  final completer = Completer<({SystemOfUnits? choice, bool applyToAll})?>();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final overlayContext = navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      completer.complete(null);
      return;
    }

    bool applyToAll = false;

    try {
      final result = await showDialog<SystemOfUnits?>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('${valueTypeName[0].toUpperCase()}${valueTypeName.substring(1)} Conflict'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The data has conflicting values:'),
                const SizedBox(height: 16),
                Text(
                  '${value.systemOfUnits.name[0].toUpperCase()}${value.systemOfUnits.name.substring(1)}: $value',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${conflictingValue.systemOfUnits.name[0].toUpperCase()}${conflictingValue.systemOfUnits.name.substring(1)}: $conflictingValue',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Apply to all remaining conflicts'),
                  value: applyToAll,
                  onChanged: (v) => setDialogState(() => applyToAll = v ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(value.systemOfUnits),
                child: Text('Use ${value.systemOfUnits.name}'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(conflictingValue.systemOfUnits),
                child: Text('Use ${conflictingValue.systemOfUnits.name}'),
              ),
            ],
          ),
        ),
      );

      if (result == null) {
        completer.complete(null);
      } else {
        completer.complete((choice: result, applyToAll: applyToAll));
      }
    } catch (e) {
      debugPrint('Conflict dialog error: $e');
      completer.complete(null);
    }
  });

  return completer.future;
}

/// A Flutter-friendly conflict resolver that shows a dialog with buttons
/// instead of the console-style text prompt.
class FlutterConflictResolver<T extends ValueType<T>>
    extends ConflictResolver<T> {
  FlutterConflictResolver(this._showDialog);

  final Future<({SystemOfUnits? choice, bool applyToAll})?> Function(
    String valueTypeName,
    T value,
    T conflictingValue,
  ) _showDialog;

  SystemOfUnits? _remembered;

  @override
  Future<(T?, String?)> resolveConflict(
    String valueTypeName,
    T value,
    T conflictingInDifferentUnit,
    String error,
  ) async {
    var systemOfUnits = _remembered;

    if (systemOfUnits == null) {
      final result = await _showDialog(
        valueTypeName,
        value,
        conflictingInDifferentUnit,
      );

      if (result == null || result.choice == null) {
        return (null, '$error. Conflict resolution cancelled by user');
      }

      systemOfUnits = result.choice!;
      if (result.applyToAll) {
        _remembered = systemOfUnits;
      }
    }

    for (var v in [value, conflictingInDifferentUnit]) {
      if (v.systemOfUnits == systemOfUnits) {
        resolutionLog.add(
          "$error. Resolved using ${systemOfUnits.name} value: '$v'.",
        );
        return (v, null);
      }
    }
    return (null, '$error. Failed to resolve conflict');
  }
}
