import 'package:flutter/material.dart';
import 'package:server_driven_ui/yaml_ui/shql_bindings.dart';

/// Minimal type resolvers you can expand.
class Resolvers {
  static MainAxisAlignment mainAxis(
    String? v, {
    MainAxisAlignment fallback = MainAxisAlignment.start,
  }) {
    switch ((v ?? '').toLowerCase()) {
      case 'start':
        return MainAxisAlignment.start;
      case 'end':
        return MainAxisAlignment.end;
      case 'center':
        return MainAxisAlignment.center;
      case 'spacebetween':
        return MainAxisAlignment.spaceBetween;
      case 'spacearound':
        return MainAxisAlignment.spaceAround;
      case 'spaceevenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return fallback;
    }
  }

  static CrossAxisAlignment crossAxis(
    String? v, {
    CrossAxisAlignment fallback = CrossAxisAlignment.center,
  }) {
    switch ((v ?? '').toLowerCase()) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'center':
        return CrossAxisAlignment.center;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      case 'baseline':
        return CrossAxisAlignment.baseline;
      default:
        return fallback;
    }
  }

  static EdgeInsets edgeInsets(dynamic v) {
    // supports: 16, [l,t,r,b], {left:16,top:8,...} or {l:16,t:8,...}
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is List && v.length == 4) {
      return EdgeInsets.fromLTRB(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
        (v[3] as num).toDouble(),
      );
    }
    if (v is Map) {
      double g(String k1, String k2) =>
          ((v[k1] ?? v[k2] ?? 0) as num).toDouble();
      return EdgeInsets.fromLTRB(
        g('left', 'l'),
        g('top', 't'),
        g('right', 'r'),
        g('bottom', 'b'),
      );
    }
    return EdgeInsets.zero;
  }

  static Color? color(dynamic v) {
    if (v is int) return Color(v);
    if (v is String) {
      final s = v.trim();
      if (s.startsWith('#')) {
        final hex = s.substring(1);
        final full = hex.length == 6 ? 'FF$hex' : hex;
        return Color(int.parse(full, radix: 16));
      }
      if (s.startsWith('0x')) {
        return Color(int.parse(s.substring(2), radix: 16));
      }
    }
    return null;
  }

  static BoxFit? boxFit(String? v) {
    switch (v?.toLowerCase()) {
      case 'fill':
        return BoxFit.fill;
      case 'contain':
        return BoxFit.contain;
      case 'cover':
        return BoxFit.cover;
      case 'fitwidth':
        return BoxFit.fitWidth;
      case 'fitheight':
        return BoxFit.fitHeight;
      case 'none':
        return BoxFit.none;
      case 'scaledown':
        return BoxFit.scaleDown;
      default:
        return null;
    }
  }

  static BorderRadius? borderRadius(dynamic v) {
    if (v is num) return BorderRadius.circular(v.toDouble());
    return null;
  }

  static TextAlign? textAlign(String? v) {
    switch (v?.toLowerCase()) {
      case 'center':
        return TextAlign.center;
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      case 'start':
        return TextAlign.start;
      case 'end':
        return TextAlign.end;
      default:
        return null;
    }
  }

  /// Maps icon name strings to Material [IconData].
  static IconData iconData(String name) {
    switch (name) {
      case 'home': return Icons.home;
      case 'search': return Icons.search;
      case 'bookmark': return Icons.bookmark;
      case 'bookmark_border': return Icons.bookmark_border;
      case 'bookmark_add': return Icons.bookmark_add;
      case 'settings': return Icons.settings;
      case 'person': return Icons.person;
      case 'person_search': return Icons.person_search;
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
      case 'select_all': return Icons.select_all;
      case 'filter_list': return Icons.filter_list;
      case 'restore': return Icons.restore;
      case 'play_arrow': return Icons.play_arrow;
      case 'save': return Icons.save;
      case 'volume_up': return Icons.volume_up;
      case 'help_outline': return Icons.help_outline;
      case 'balance': return Icons.balance;
      case 'verified_user': return Icons.verified_user;
      case 'thumb_up': return Icons.thumb_up;
      case 'warning_amber': return Icons.warning_amber;
      case 'whatshot': return Icons.whatshot;
      case 'mood_bad': return Icons.mood_bad;
      case 'local_fire_department': return Icons.local_fire_department;
      case 'psychology': return Icons.psychology;
      case 'fitness_center': return Icons.fitness_center;
      case 'speed': return Icons.speed;
      case 'bolt': return Icons.bolt;
      case 'sports_mma': return Icons.sports_mma;
      default: return Icons.help_outline;
    }
  }

  static Alignment? alignment(String? v) {
    switch (v?.toLowerCase()) {
      case 'topleft':
        return Alignment.topLeft;
      case 'topcenter':
        return Alignment.topCenter;
      case 'topright':
        return Alignment.topRight;
      case 'centerleft':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerright':
        return Alignment.centerRight;
      case 'bottomleft':
        return Alignment.bottomLeft;
      case 'bottomcenter':
        return Alignment.bottomCenter;
      case 'bottomright':
        return Alignment.bottomRight;
      default:
        return null;
    }
  }
}

Map<String, dynamic> resolveMap(Map map, ShqlBindings shql) {
  final newMap = <String, dynamic>{};
  for (var entry in map.entries) {
    newMap[entry.key.toString()] = entry.value;
  }
  return newMap;
}
