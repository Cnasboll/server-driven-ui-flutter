import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';

/// Generates a SHQL™ schema script from the [HeroModel] Field tree.
///
/// The generated script defines:
/// 1. NVL accessor functions (BIOGRAPHY, POWERSTATS, etc.)
/// 2. Value type helpers (HEIGHT_M, WEIGHT_KG)
/// 3. `_detail_fields` metadata for GENERATE_HERO_DETAIL()
/// 4. `_summary_fields` metadata for GENERATE_HERO_CARDS()
///
/// All field names, display labels, and SHQL™ identifiers are derived from the
/// Field tree — no hardcoded strings. This is the single source of truth.
class HeroSchema {
  HeroSchema._();

  // Positional color palette for stat sections — assigned by child index,
  // not keyed by field name.
  static const _statColorPalette = [
    '0xFF2196F3', '0xFFF44336', '0xFFFF9800',
    '0xFF4CAF50', '0xFF9C27B0', '0xFF795548',
  ];

  /// Converts snake_case to camelCase: `'full_name'` → `'fullName'`
  static String _snakeToCamelCase(String s) {
    final parts = s.split('_');
    return parts.first +
        parts.skip(1).map((p) => '${p[0].toUpperCase()}${p.substring(1)}').join();
  }

  /// Generates the complete SHQL™ schema script.
  static String generateSchemaScript() {
    final sb = StringBuffer();
    sb.writeln('-- ============================================');
    sb.writeln('-- Auto-generated HeroSchema (from Field tree)');
    sb.writeln('-- ============================================');
    sb.writeln();

    _generateAccessors(sb);
    _generateValueTypeHelpers(sb);
    _generateDetailFields(sb);
    _generateSummaryFields(sb);

    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // NVL Accessor Functions
  // ---------------------------------------------------------------------------

  static void _generateAccessors(StringBuffer sb) {
    sb.writeln('-- NVL accessor functions');
    for (final field in HeroModel.staticFields) {
      final f = field as dynamic;
      final children = f.children as List<FieldBase>;
      final childrenForDbOnly = f.childrenForDbOnly as bool;
      if (children.isEmpty || childrenForDbOnly) continue;

      final name = (f.shqlName as String).toUpperCase();
      sb.writeln(
        '$name(hero, f, default) := NVL(NVL(NVL(hero, h => h.$name, null), f, null), v => v, default);',
      );
    }
    sb.writeln();
  }

  // ---------------------------------------------------------------------------
  // Value Type Helpers
  // ---------------------------------------------------------------------------

  static void _generateValueTypeHelpers(StringBuffer sb) {
    sb.writeln('-- Value type helpers');
    for (final topField in HeroModel.staticFields) {
      final tf = topField as dynamic;
      final topChildren = tf.children as List<FieldBase>;
      if (topChildren.isEmpty) continue;

      for (final childField in topChildren) {
        final cf = childField as dynamic;
        final grandChildren = cf.children as List<FieldBase>;
        final childrenForDbOnly = cf.childrenForDbOnly as bool;
        if (!childrenForDbOnly || grandChildren.isEmpty) continue;

        final parentAccessor = (tf.shqlName as String).toUpperCase();
        final valueTypeName = (cf.shqlName as String).toUpperCase();
        final primaryChild = grandChildren.first as dynamic;
        final primaryChildName = (primaryChild.shqlName as String).toUpperCase();
        final helperName = '${valueTypeName}_$primaryChildName';

        sb.writeln(
          '$helperName(hero, default) := BEGIN '
          'v := NVL($parentAccessor(hero, a => a.$valueTypeName, null), x => x.$primaryChildName, null); '
          'RETURN IF v = null OR v <= 0 THEN default ELSE v; '
          'END;',
        );
      }
    }
    sb.writeln();
  }

  // ---------------------------------------------------------------------------
  // _detail_fields metadata
  // ---------------------------------------------------------------------------

  static void _generateDetailFields(StringBuffer sb) {
    sb.writeln('-- Detail fields metadata');
    sb.write('_detail_fields := [');

    var first = true;
    for (final topField in HeroModel.staticFields) {
      final tf = topField as dynamic;
      final assignedBySystem = tf.assignedBySystem as bool;
      final mutable = tf.mutable as bool;
      final topChildren = tf.children as List<FieldBase>;

      if (assignedBySystem && !mutable) continue;

      if (topChildren.isNotEmpty) {
        final childrenForDbOnly = tf.childrenForDbOnly as bool;
        if (childrenForDbOnly) continue;

        final showInDetail = tf.showInDetail as bool;
        if (!showInDetail) continue;

        final section = tf.displayName as String;
        final parentShqlName = (tf.shqlName as String).toUpperCase();
        final isStatSection = parentShqlName == 'POWERSTATS';

        for (var childIndex = 0; childIndex < topChildren.length; childIndex++) {
          final cf = topChildren[childIndex] as dynamic;
          final cfChildren = cf.children as List<FieldBase>;
          final cfChildrenForDbOnly = cf.childrenForDbOnly as bool;
          final childShqlName = (cf.shqlName as String).toUpperCase();
          final childShqlNameLower = cf.shqlName as String;
          final label = cf.name as String;

          if (!first) sb.write(',');
          first = false;
          sb.writeln();

          if (cfChildrenForDbOnly && cfChildren.isNotEmpty) {
            // Value type (Height, Weight) — use the generated helper
            final primaryChild = cfChildren.first as dynamic;
            final primaryChildName = (primaryChild.shqlName as String).toUpperCase();
            final helperName = '${childShqlName}_$primaryChildName';
            final unit = primaryChildName.toLowerCase();
            sb.write(
              '    OBJECT{section: \'$section\', label: \'$label\', '
              'accessor: (hero) => $helperName(hero, 0), '
              'display_type: \'measurement\', unit: \'$unit\'}',
            );
          } else if (HeroShqlAdapter.enumLabelsFor(childShqlNameLower) != null) {
            // Enum field — label variable retrieved from HeroShqlAdapter
            final enumLabelsVar = HeroShqlAdapter.enumLabelsFor(childShqlNameLower)!;
            sb.write(
              '    OBJECT{section: \'$section\', label: \'$label\', '
              'accessor: (hero) => $parentShqlName(hero, x => x.$childShqlName, 0), '
              'display_type: \'enum_label\', enum_labels: $enumLabelsVar}',
            );
          } else if (isStatSection) {
            // Stat field — color from positional palette
            final color = _statColorPalette[childIndex % _statColorPalette.length];
            sb.write(
              '    OBJECT{section: \'$section\', label: \'$label\', '
              'accessor: (hero) => $parentShqlName(hero, x => x.$childShqlName, 0), '
              'display_type: \'stat\', color: \'$color\'}',
            );
          } else {
            // Regular text field
            sb.write(
              '    OBJECT{section: \'$section\', label: \'$label\', '
              'accessor: (hero) => $parentShqlName(hero, x => x.$childShqlName, \'Unknown\'), '
              'display_type: \'text\'}',
            );
          }
        }
      } else {
        // Top-level leaf (name) — shown in AppBar, not in detail cards
        continue;
      }
    }

    sb.writeln();
    sb.writeln('];');
    sb.writeln();
  }

  // ---------------------------------------------------------------------------
  // _summary_fields metadata
  // ---------------------------------------------------------------------------

  static void _generateSummaryFields(StringBuffer sb) {
    sb.writeln('-- Summary fields metadata (for HeroCard)');
    sb.write('_summary_fields := [');

    var first = true;
    // Track PowerStats accessor + children for totalPower generation
    String? statsAccessor;
    List<FieldBase>? statsChildren;

    for (final topField in HeroModel.staticFields) {
      final tf = topField as dynamic;
      final topChildren = tf.children as List<FieldBase>;
      final topShqlNameLower = tf.shqlName as String;
      final topShqlName = topShqlNameLower.toUpperCase();
      final topShowInSummary = tf.showInSummary as bool;

      if (topChildren.isEmpty) {
        // Top-level leaf field
        if (!topShowInSummary) continue;
        final propName = _snakeToCamelCase(topShqlNameLower);

        if (!first) sb.write(',');
        first = false;
        sb.writeln();
        sb.write(
          '    OBJECT{prop_name: \'$propName\', accessor: (hero) => hero.$topShqlName}',
        );
      } else {
        final childrenForDbOnly = tf.childrenForDbOnly as bool;
        if (childrenForDbOnly) continue;

        for (final childField in topChildren) {
          final cf = childField as dynamic;
          final childShowInSummary = cf.showInSummary as bool;
          if (!childShowInSummary) continue;

          final childShqlNameLower = cf.shqlName as String;
          final childShqlName = childShqlNameLower.toUpperCase();
          final propName = _snakeToCamelCase(childShqlNameLower);

          if (!first) sb.write(',');
          first = false;
          sb.writeln();

          // Default: 0 for enums/stats, '' for text
          final enumLabels = HeroShqlAdapter.enumLabelsFor(childShqlNameLower);
          final isStatChild = topShqlName == 'POWERSTATS';
          final defaultVal = (enumLabels != null || isStatChild) ? '0' : "''";
          sb.write(
            '    OBJECT{prop_name: \'$propName\', '
            'accessor: (hero) => $topShqlName(hero, x => x.$childShqlName, $defaultVal)}',
          );
        }

        // Remember PowerStats for totalPower generation
        if (topShqlName == 'POWERSTATS') {
          statsAccessor = topShqlName;
          statsChildren = topChildren;
        }
      }
    }

    // Computed: totalPower — iterate PowerStats children
    if (statsAccessor != null && statsChildren != null) {
      final sumParts = statsChildren.map((c) {
        final name = ((c as dynamic).shqlName as String).toUpperCase();
        return '$statsAccessor(hero, p => p.$name, 0)';
      }).join(' + ');
      sb.write(',');
      sb.writeln();
      sb.write(
        '    OBJECT{prop_name: \'totalPower\', accessor: (hero) => $sumParts}',
      );
    }

    sb.writeln();
    sb.writeln('];');
  }
}
