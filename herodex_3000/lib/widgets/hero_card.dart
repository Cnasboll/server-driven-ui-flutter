import 'package:flutter/material.dart';

/// Static utility methods for hero card alignment styles.
///
/// The actual card widget tree is built entirely by the `HeroCard` factory
/// in `herodex_widget_registry.dart` using `buildChild` — SHQL™ expression
/// strings flow through the registry to leaf widgets (InkWell, etc.) where
/// `_resolveOnPressed` evaluates them against the real SHQL™ runtime.
class HeroCard {
  HeroCard._();

  // Indexed by Alignment enum ordinal (hero_common/lib/models/biography_model.dart)
  static const _alignmentStyles = <({String label, String icon, List<Color> gradient})>[
    /* 0 */ (label: 'Unknown',       icon: 'help_outline',          gradient: [Color(0xFF9E9E9E), Color(0xFF616161)]),
    /* 1 */ (label: 'Neutral',       icon: 'balance',               gradient: [Color(0xFF78909C), Color(0xFF455A64)]),
    /* 2 */ (label: 'Mostly Good',   icon: 'verified_user',         gradient: [Color(0xFF29B6F6), Color(0xFF1E88E5)]),
    /* 3 */ (label: 'Good',          icon: 'shield',                gradient: [Color(0xFF42A5F5), Color(0xFF00897B)]),
    /* 4 */ (label: 'Reasonable',    icon: 'thumb_up',              gradient: [Color(0xFF7986CB), Color(0xFF3949AB)]),
    /* 5 */ (label: 'Not Quite',     icon: 'warning_amber',         gradient: [Color(0xFFFFA726), Color(0xFFE64A19)]),
    /* 6 */ (label: 'Bad',           icon: 'whatshot',               gradient: [Color(0xFFE53935), Color(0xFF4A0000)]),
    /* 7 */ (label: 'Ugly',          icon: 'mood_bad',              gradient: [Color(0xFFC62828), Color(0xFF3A0000)]),
    /* 8 */ (label: 'Evil',          icon: 'local_fire_department', gradient: [Color(0xFF8B0000), Color(0xFF1A0000)]),
    /* 9 */ (label: 'Using Mobile Speaker on Public Transport', icon: 'volume_up', gradient: [Color(0xFF0D0000), Color(0xFF000000)]),
  ];

  /// Returns the primary alignment colour for a given alignment ordinal.
  static Color alignmentColorFor(int alignment) =>
      (alignment >= 0 && alignment < _alignmentStyles.length)
          ? _alignmentStyles[alignment].gradient.first
          : _alignmentStyles[0].gradient.first;

  /// Returns the alignment gradient for a given alignment ordinal.
  static List<Color> alignmentGradientFor(int alignment) =>
      (alignment >= 0 && alignment < _alignmentStyles.length)
          ? _alignmentStyles[alignment].gradient
          : _alignmentStyles[0].gradient;

  /// Returns the alignment icon name for a given alignment ordinal.
  static String alignmentIconFor(int alignment) =>
      (alignment >= 0 && alignment < _alignmentStyles.length)
          ? _alignmentStyles[alignment].icon
          : _alignmentStyles[0].icon;

  /// Returns the alignment label for a given alignment ordinal.
  static String alignmentLabelFor(int alignment) =>
      (alignment >= 0 && alignment < _alignmentStyles.length)
          ? _alignmentStyles[alignment].label
          : _alignmentStyles[0].label;

  /// Compute the semantics label for a hero card.
  static String semanticsLabel(String name, int alignment, List<Map<String, dynamic>> stats) {
    final label = alignmentLabelFor(alignment);
    final sb = StringBuffer('$name, $label alignment');
    for (final stat in stats) {
      final l = stat['label'] as String?;
      final v = stat['value'];
      if (l != null && v != null) sb.write(', $l $v');
    }
    return sb.toString();
  }

  /// Compute publisher/race subtitle.
  static String subtitle(String? publisher, String? race) {
    final parts = <String>[];
    if (publisher != null && publisher.isNotEmpty) parts.add(publisher);
    if (race != null && race.isNotEmpty) parts.add(race);
    return parts.join(' \u2022 ');
  }
}
