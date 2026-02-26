import 'dart:math';

import 'package:flutter/material.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

import '../widgets/hero_card.dart';
import '../widgets/battle_map_widget.dart';

/// Compute a 10% alpha background hex string from a foreground color hex.
String _statBgColor(dynamic raw) {
  if (raw is String && raw.startsWith('0x') && raw.length >= 10) {
    // Parse the hex, set alpha to ~10% (0x1A = 26/255 ≈ 10%)
    final hex = raw.substring(4); // strip '0xFF' prefix
    return '0x1A$hex';
  }
  return '0x1A9E9E9E';
}

/// Creates a [WidgetRegistry] with HeroDex-specific custom widgets
/// layered on top of the basic SDUI widgets.
WidgetRegistry createHeroDexWidgetRegistry() {
  final basicRegistry = WidgetRegistry.basic();

  final customFactories = <String, WidgetFactory>{
    'HeroCard':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          // Build stat chip rows via the registry (StatChip is YAML-defined)
          final rawStats = props['stats'];
          final stats = <Map<String, dynamic>>[];
          if (rawStats is List) {
            for (final s in rawStats) {
              if (s is Map<String, dynamic>) {
                stats.add(s);
              } else if (s is Map) {
                stats.add(Map<String, dynamic>.from(s));
              }
            }
          }

          const perRow = 3;
          final statRows = <Widget>[];
          for (var rowStart = 0; rowStart < stats.length; rowStart += perRow) {
            if (rowStart > 0) {
              statRows.add(buildChild(
                {'type': 'SizedBox', 'props': {'height': 4}},
                '$path.statGap[$rowStart]',
              ));
            }
            final rowEnd = min(rowStart + perRow, stats.length);
            final rowChildren = <dynamic>[];
            for (var i = rowStart; i < rowEnd; i++) {
              if (i > rowStart) {
                rowChildren.add({'type': 'SizedBox', 'props': {'width': 4}});
              }
              rowChildren.add({
                'type': 'StatChip',
                'props': {
                  'label': stats[i]['label'] as String? ?? '?',
                  'valueText': (stats[i]['value']?.toString()) ?? '-',
                  'color': stats[i]['color'] as String? ?? '0xFF9E9E9E',
                  'bgColor': _statBgColor(stats[i]['color']),
                },
              });
            }
            statRows.add(buildChild(
              {'type': 'Row', 'children': rowChildren},
              '$path.statRow[$rowStart]',
            ));
          }

          // Build power bar via the registry (PowerBar is YAML-defined)
          final totalPower = props['totalPower'] as int?;
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final alignment = props['alignment'] as int? ?? 0;
          final alignmentColor = HeroCard.alignmentColorFor(alignment);
          Widget? powerBarWidget;
          if (totalPower != null) {
            powerBarWidget = buildChild({
              'type': 'PowerBar',
              'props': {
                'label': 'Total Power: $totalPower',
                'progress': (totalPower / 600).clamp(0.0, 1.0),
                'color': '0x${alignmentColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                'bgColor': isDark ? '0xFF616161' : '0xFFE0E0E0',
              },
            }, '$path.powerBar');
          }

          return HeroCard(
            key: key,
            name: props['name'] as String? ?? 'Unknown',
            imageUrl: props['url'] as String? ?? props['imageUrl'] as String?,
            alignment: alignment,
            stats: stats,
            statRows: statRows,
            powerBar: powerBarWidget,
            publisher: props['publisher'] as String?,
            race: props['race'] as String?,
            fullName: props['fullName'] as String?,
            locked: props['locked'] as bool? ?? false,
            onTap: props['onTap'] != null
                ? () => WidgetRegistry.callShql(context, shql, props['onTap'] as String)
                : null,
            onDelete: props['onDelete'] != null
                ? () => WidgetRegistry.callShql(context, shql, props['onDelete'] as String)
                : null,
            onToggleLock: props['onToggleLock'] != null
                ? () => WidgetRegistry.callShql(context, shql, props['onToggleLock'] as String)
                : null,
          );
        },
    'BattleMap':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final lat = (props['latitude'] as num?)?.toDouble() ?? 56.28;
          final lon = (props['longitude'] as num?)?.toDouble() ?? 13.28;
          final zoom = (props['zoom'] as num?)?.toDouble() ?? 10;
          final rawMarkers = props['markers'];
          final markers = <Map<String, dynamic>>[];
          if (rawMarkers is List) {
            for (final m in rawMarkers) {
              if (m is Map<String, dynamic>) {
                markers.add(m);
              } else {
                markers.add(shql.objectToMap(m));
              }
            }
          }
          return BattleMapWidget(
            key: key,
            latitude: lat,
            longitude: lon,
            zoom: zoom,
            markers: markers,
          );
        },
  };

  return HeroDexWidgetRegistry(basicRegistry, customFactories);
}

/// Extended WidgetRegistry that adds HeroDex custom widgets on top of basic ones.
class HeroDexWidgetRegistry extends WidgetRegistry {
  final WidgetRegistry _basicRegistry;
  final Map<String, WidgetFactory> _customFactories;

  HeroDexWidgetRegistry(this._basicRegistry, this._customFactories)
    : super({});

  @override
  WidgetFactory? get(String type) {
    if (_customFactories.containsKey(type)) {
      return _customFactories[type];
    }
    return _basicRegistry.get(type) ?? super.get(type);
  }

  @override
  Widget build({
    required String type,
    required BuildContext context,
    required Map<String, dynamic> props,
    required ChildBuilder buildChild,
    required dynamic child,
    required dynamic children,
    required String path,
    required ShqlBindings shql,
    required YamlUiEngine engine,
  }) {
    if (_customFactories.containsKey(type)) {
      final key = ValueKey<String>(path);
      return _customFactories[type]!(
        context, props, buildChild, child, children, path, shql, key, engine,
      );
    }
    if (_basicRegistry.get(type) != null) {
      return _basicRegistry.build(
        type: type,
        context: context,
        props: props,
        buildChild: buildChild,
        child: child,
        children: children,
        path: path,
        shql: shql,
        engine: engine,
      );
    }
    // Fall through to base class — handles YAML-defined widget templates
    // registered via registerTemplate().
    return super.build(
      type: type,
      context: context,
      props: props,
      buildChild: buildChild,
      child: child,
      children: children,
      path: path,
      shql: shql,
      engine: engine,
    );
  }
}
