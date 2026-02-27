import 'package:flutter/foundation.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:server_driven_ui/server_driven_ui.dart';
import 'package:shql/tokenizer/string_escaper.dart';

/// Compiles SHQL™ filter predicates into lambdas and publishes them to the
/// SHQL™ runtime as `_filter_lambdas`. Hero evaluation against filters is
/// handled entirely by SHQL™ (ON_HERO_ADDED, REBUILD_ALL_FILTERS).
class FilterCompiler {
  FilterCompiler(this._shqlBindings);

  final ShqlBindings _shqlBindings;

  /// filterName → compiled SHQL™ lambda
  final Map<String, dynamic> _lambdas = {};

  /// filterName → predicate text (for change detection and evaluation)
  final Map<String, String> _predicateTexts = {};

  /// Read-only view of compiled lambdas.
  Map<String, dynamic> get compiledLambdas =>
      Map<String, dynamic>.unmodifiable(_lambdas);

  /// Read-only view of predicate texts.
  Map<String, String> get predicateTexts =>
      Map<String, String>.unmodifiable(_predicateTexts);

  // ---------------------------------------------------------------------------
  // Predicate compilation
  // ---------------------------------------------------------------------------

  static final String _heroParams = HeroModel.staticFields
      .map((f) => (f as dynamic).shqlName as String)
      .join(', ');
  static final String _heroArgs = HeroModel.staticFields
      .map((f) => 'hero.${((f as dynamic).shqlName as String).toUpperCase()}')
      .join(', ');

  /// Compiles a single predicate expression into an SHQL™ lambda: hero -> bool.
  Future<dynamic> compilePredicate(String expr) async {
    return await _shqlBindings.eval(
      'hero => BEGIN __f($_heroParams) := $expr; __f($_heroArgs) END',
    );
  }

  /// Compiles a text search into an SHQL™ lambda that calls the MATCH callback.
  Future<dynamic> compileTextMatch(String text) async {
    final escaped = StringEscaper.escape(text);
    return await _shqlBindings.eval('hero => MATCH(hero, "$escaped")');
  }

  /// Compile a query into a lambda — predicate if valid, text-match otherwise.
  Future<dynamic> compileQuery(String query) async {
    if (await isValidPredicate(query)) {
      return compilePredicate(query);
    }
    return compileTextMatch(query);
  }

  /// (Re)compile all filter predicates from the current `_filters` SHQL™
  /// variable. Only recompiles predicates that have changed.
  Future<void> compileFilterPredicates() async {
    final filters = _shqlBindings.getVariable('_filters');
    if (filters is! List) {
      debugPrint('[FilterCompiler] _filters is not a List: ${filters.runtimeType}');
      _lambdas.clear();
      _predicateTexts.clear();
      return;
    }

    debugPrint('[FilterCompiler] compileFilterPredicates: ${filters.length} filters');
    final currentNames = <String>{};

    for (int idx = 0; idx < filters.length; idx++) {
      final f = filters[idx];
      final m = _shqlBindings.objectToMap(f);
      final name = (m['name'] as String?) ?? '';
      final expr = (m['predicate'] as String?) ?? '';
      currentNames.add(name);
      debugPrint('[FilterCompiler]   [$idx] name="$name" predicate="${expr.length > 40 ? '${expr.substring(0, 40)}...' : expr}"');

      // Skip if unchanged
      if (_predicateTexts[name] == expr) {
        debugPrint('[FilterCompiler]   [$idx] SKIPPED (unchanged)');
        continue;
      }

      _predicateTexts[name] = expr;

      if (expr.isEmpty) {
        _lambdas.remove(name);
        debugPrint('[FilterCompiler]   [$idx] empty predicate → removed');
      } else if (await isValidPredicate(expr)) {
        _lambdas[name] = await compilePredicate(expr);
        debugPrint('[FilterCompiler]   [$idx] compiled as PREDICATE');
      } else {
        _lambdas[name] = await compileTextMatch(expr);
        debugPrint('[FilterCompiler]   [$idx] compiled as TEXT MATCH');
      }
    }

    // Remove deleted filters
    final removed = _lambdas.keys.where((n) => !currentNames.contains(n)).toSet();
    for (final name in removed) {
      _lambdas.remove(name);
      _predicateTexts.remove(name);
      debugPrint('[FilterCompiler] removed stale lambda: "$name"');
    }
    debugPrint('[FilterCompiler] final _lambdas keys: ${_lambdas.keys.toList()}');
  }

  /// Compile all filter predicates and publish the lambda map to SHQL™
  /// as `_filter_lambdas`. SHQL™'s `ON_HERO_ADDED` and `REBUILD_ALL_FILTERS`
  /// read this variable to evaluate heroes against filters.
  Future<void> compileAndPublish() async {
    await compileFilterPredicates();
    _shqlBindings.setVariable('_filter_lambdas', Map<String, dynamic>.from(_lambdas));
  }

  // ---------------------------------------------------------------------------
  // Predicate validation
  // ---------------------------------------------------------------------------

  /// Build a fully-populated mock hero JSON from the Field tree.
  /// Every key and nested structure is discovered from field metadata —
  /// no hardcoded field names.
  static Map<String, dynamic> _buildMockHeroJson() {
    final json = <String, dynamic>{'response': 'success'};
    _populateFromFields(json, HeroModel.staticFields);
    return json;
  }

  static void _populateFromFields(
    Map<String, dynamic> json,
    List<FieldBase> fields,
  ) {
    for (final field in fields) {
      final f = field as dynamic;
      final jsonName = f.jsonName as String;
      final children = f.children as List<FieldBase>;
      final childrenForDbOnly = f.childrenForDbOnly as bool;
      final description = f.description as String;
      final primary = f.primary as bool;

      if (children.isNotEmpty && !childrenForDbOnly) {
        // Section with real children — recurse
        final childJson = <String, dynamic>{};
        _populateFromFields(childJson, children);
        json[jsonName] = childJson;
      } else if (children.isNotEmpty && childrenForDbOnly) {
        // Value type (Height, Weight) — parseable single-value array
        json[jsonName] = ['100'];
      } else if (primary) {
        json[jsonName] = '69';
      } else if (description == '%') {
        json[jsonName] = '50';
      } else {
        json[jsonName] = 'Test';
      }
    }
  }

  static HeroModel? _mockHero;

  Future<HeroModel> _getMockHero() async {
    _mockHero ??= await HeroModel.fromJson(
      _buildMockHeroJson(), DateTime(2025, 1, 1),
    );
    return _mockHero!;
  }

  /// Test whether [expr] is a valid SHQL™ predicate by evaluating it against
  /// a canonical mock hero.
  Future<bool> isValidPredicate(String expr) async {
    if (expr.isEmpty) return false;
    try {
      final testHero = await _getMockHero();
      final boundValues = HeroShqlAdapter.heroToBoundValues(
        testHero, _shqlBindings.identifiers,
      );
      final result = await _shqlBindings.eval(expr, boundValues: boundValues);
      // Must return a bool — plain text like "batman" returns null (undefined
      // SHQL™ identifier) and should fall through to text-match, not be
      // compiled as a predicate that silently rejects every hero.
      return result is bool;
    } catch (_) {
      return false;
    }
  }
}
