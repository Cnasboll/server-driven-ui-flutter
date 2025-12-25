import 'package:flutter/material.dart';
import 'package:server_driven_ui/server_driven_ui.dart';
import 'package:server_driven_ui/yaml_ui/resolvers.dart';

import '../widgets/hero_card.dart';
import '../widgets/battle_map_widget.dart';
import '../widgets/animated_number_widget.dart';

/// Creates a [WidgetRegistry] with HeroDex-specific custom widgets
/// layered on top of the basic SDUI widgets.
WidgetRegistry createHeroDexWidgetRegistry() {
  final basicRegistry = WidgetRegistry.basic();

  final customFactories = <String, WidgetFactory>{
    'HeroCard':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          return HeroCard(
            key: key,
            name: props['name'] as String? ?? 'Unknown',
            imageUrl: props['url'] as String? ?? props['imageUrl'] as String?,
            alignment: props['alignment'] as int? ?? 0,
            strength: props['strength'] as int?,
            intelligence: props['intelligence'] as int?,
            speed: props['speed'] as int?,
            durability: props['durability'] as int?,
            power: props['power'] as int?,
            combat: props['combat'] as int?,
            totalPower: props['totalPower'] as int?,
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
    'IconButton':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final iconName = props['icon'] as String?;
          final onPressed = props['onPressed'] as String?;

          IconData iconData = Icons.help_outline;
          if (iconName != null) {
            iconData = getIconData(iconName);
          }

          VoidCallback? onPressedCallback;
          if (onPressed != null && isShqlRef('shql: $onPressed')) {
            onPressedCallback = () => WidgetRegistry.callShql(context, shql, onPressed);
          }

          return IconButton(
            key: key,
            icon: Icon(iconData),
            onPressed: onPressedCallback,
          );
        },
    'Icon':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final iconName = props['icon'] as String? ?? 'help_outline';
          final size = (props['size'] as num?)?.toDouble();
          final colorValue = props['color'];

          Color? color;
          if (colorValue is String && colorValue.startsWith('0x')) {
            color = Color(int.parse(colorValue));
          }

          return Icon(getIconData(iconName), key: key, size: size, color: color);
        },
    'BottomNavigationBar':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final items = props['items'] as List? ?? [];
          final currentIndex = props['currentIndex'] as int? ?? 0;
          final onTap = props['onTap'] as String?;

          return BottomNavigationBar(
            key: key,
            currentIndex: currentIndex,
            onTap: onTap != null ? (index) {
              WidgetRegistry.callShql(context, shql, onTap.replaceAll('value', '$index'));
            } : null,
            items: items.map<BottomNavigationBarItem>((item) {
              final map = item as Map;
              return BottomNavigationBarItem(
                icon: Icon(getIconData(map['icon'] as String? ?? 'help')),
                label: map['label'] as String? ?? '',
              );
            }).toList(),
          );
        },
    'SafeArea':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final childNode = props['child'] ?? child;
          return SafeArea(
            key: key,
            child: childNode != null
                ? buildChild(childNode, '$path.child')
                : const SizedBox.shrink(),
          );
        },
    'ListTile':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final leadingNode = props['leading'];
          final titleNode = props['title'];
          final subtitleNode = props['subtitle'];
          final trailingNode = props['trailing'];
          final onTap = props['onTap'] as String?;

          VoidCallback? onTapCallback;
          if (onTap != null && isShqlRef(onTap)) {
            final (:code, :targeted) = parseShql(onTap);
            onTapCallback = () => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
          }

          return ListTile(
            key: key,
            leading: leadingNode != null ? buildChild(leadingNode, '$path.leading') : null,
            title: titleNode != null ? buildChild(titleNode, '$path.title') : null,
            subtitle: subtitleNode != null ? buildChild(subtitleNode, '$path.subtitle') : null,
            trailing: trailingNode != null ? buildChild(trailingNode, '$path.trailing') : null,
            onTap: onTapCallback,
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
    'AnimatedNumber':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final rawValue = props['value'];
          final value = rawValue is num
              ? rawValue
              : num.tryParse(rawValue?.toString() ?? '') ?? 0;
          final duration = (props['duration'] as int?) ?? 800;
          final fontSize = (props['fontSize'] as num?)?.toDouble();
          final fontWeight = props['fontWeight']?.toString();
          final color = props['color'];
          return AnimatedNumber(
            key: key,
            value: value,
            duration: Duration(milliseconds: duration),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight == 'bold' ? FontWeight.bold : null,
              color: color != null ? Resolvers.color(color) : null,
            ),
          );
        },
  };

  return HeroDexWidgetRegistry(basicRegistry, customFactories);
}

/// Maps icon name strings to Material [IconData].
IconData getIconData(String name) {
  switch (name) {
    case 'home': return Icons.home;
    case 'search': return Icons.search;
    case 'bookmark': return Icons.bookmark;
    case 'bookmark_border': return Icons.bookmark_border;
    case 'bookmark_add': return Icons.bookmark_add;
    case 'settings': return Icons.settings;
    case 'person': return Icons.person;
    case 'shield': return Icons.shield;
    case 'star': return Icons.star;
    case 'favorite': return Icons.favorite;
    case 'favorite_border': return Icons.favorite_border;
    case 'delete': return Icons.delete;
    case 'delete_forever': return Icons.delete_forever;
    case 'arrow_back': return Icons.arrow_back;
    case 'analytics': return Icons.analytics;
    case 'bug_report': return Icons.bug_report;
    case 'location_on': return Icons.location_on;
    case 'map': return Icons.map;
    case 'dark_mode': return Icons.dark_mode;
    case 'light_mode': return Icons.light_mode;
    case 'info': return Icons.info;
    case 'error': return Icons.error;
    case 'warning': return Icons.warning;
    case 'check_circle': return Icons.check_circle;
    case 'close': return Icons.close;
    case 'add': return Icons.add;
    case 'remove': return Icons.remove;
    case 'edit': return Icons.edit;
    case 'lock': return Icons.lock;
    case 'lock_open': return Icons.lock_open;
    case 'vpn_key': return Icons.vpn_key;
    case 'sync': return Icons.sync;
    case 'logout': return Icons.logout;
    case 'code': return Icons.code;
    case 'calendar_today': return Icons.calendar_today;
    case 'military_tech': return Icons.military_tech;
    case 'flash_on': return Icons.flash_on;
    case 'dangerous': return Icons.dangerous;
    case 'label': return Icons.label;
    case 'wb_sunny': return Icons.wb_sunny;
    case 'cloud': return Icons.cloud;
    case 'foggy': return Icons.foggy;
    case 'water_drop': return Icons.water_drop;
    case 'ac_unit': return Icons.ac_unit;
    case 'thermostat': return Icons.thermostat;
    case 'air': return Icons.air;
    default: return Icons.help_outline;
  }
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
    return _basicRegistry.get(type);
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
}
