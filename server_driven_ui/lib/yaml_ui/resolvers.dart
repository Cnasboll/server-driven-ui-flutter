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
    // supports: 16, [l,t,r,b], {l:16,t:8,r:16,b:8}
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
      double g(String k) => ((v[k] ?? 0) as num).toDouble();
      return EdgeInsets.fromLTRB(g('l'), g('t'), g('r'), g('b'));
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
}

Map<String, dynamic> resolveMap(Map map, ShqlBindings shql) {
  final newMap = <String, dynamic>{};
  for (var entry in map.entries) {
    newMap[entry.key.toString()] = entry.value;
  }
  return newMap;
}
