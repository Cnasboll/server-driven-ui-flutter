import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hero_common/value_types/conflict_resolver.dart';
import 'package:hero_common/value_types/value_type.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

/// Actions for the one-by-one hero review dialog.
enum ReviewAction { save, skip, saveAll, cancel }

Widget _b(BuildContext c, Map<String, dynamic> node, String p) =>
    WidgetRegistry.buildStatic(c, node, 'conflict.$p');

/// Shows a height/weight conflict resolution dialog.
/// Returns the chosen system of units and whether to apply to all, or null if cancelled.
///
/// Uses SHQL™ variables for dialog state:
///   _CONFLICT_VALUE1_ID, _CONFLICT_VALUE2_ID — unit identifiers returned by CLOSE_DIALOG
///   _APPLY_TO_ALL — checkbox state, toggled by SET() in the YAML template
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

    // Initialize SHQL™ variables for the ConflictDialog template
    final shql = WidgetRegistry.staticShql;
    shql.setVariable('_CONFLICT_VALUE1_ID', value.systemOfUnits.name);
    shql.setVariable('_CONFLICT_VALUE2_ID', conflictingValue.systemOfUnits.name);
    shql.setVariable('_APPLY_TO_ALL', false);

    try {
      final result = await showDialog<dynamic>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (ctx) => _b(ctx, {'type': 'ConflictDialog', 'props': {
          'title': '${valueTypeName[0].toUpperCase()}${valueTypeName.substring(1)} Conflict',
          'value1Text': '${value.systemOfUnits.name[0].toUpperCase()}${value.systemOfUnits.name.substring(1)}: $value',
          'value2Text': '${conflictingValue.systemOfUnits.name[0].toUpperCase()}${conflictingValue.systemOfUnits.name.substring(1)}: $conflictingValue',
          'useValue1Label': 'Use ${value.systemOfUnits.name}',
          'useValue2Label': 'Use ${conflictingValue.systemOfUnits.name}',
        }}, 'dialog') as AlertDialog,
      );

      // CLOSE_DIALOG returns OBJECT{choice, applyToAll} or NULL
      if (result is Map) {
        final choiceName = result['choice'] as String?;
        // SHQL™ objectToMap() lowercases all keys: applyToAll → applytoall
        final applyToAll = result['applytoall'] == true;
        final choice = SystemOfUnits.values.where((s) => s.name == choiceName).firstOrNull;
        if (choice != null) {
          completer.complete((choice: choice, applyToAll: applyToAll));
          return;
        }
      }
      completer.complete(null);
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
