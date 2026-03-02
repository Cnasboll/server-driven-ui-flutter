import 'package:flutter/foundation.dart';
import 'package:hero_common/managers/hero_data_managing.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/models/search_response_model.dart';
import 'package:hero_common/services/hero_servicing.dart';
import 'package:hero_common/value_types/conflict_resolver.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/value_types/weight.dart';
import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/models/appearance_model.dart' show Gender;
import 'package:hero_common/models/biography_model.dart' as bio;
import 'package:server_driven_ui/server_driven_ui.dart';

import '../widgets/conflict_resolver_dialog.dart' show ReviewAction;
import '../persistence/filter_compiler.dart';

/// Callback typedefs for UI interactions that the coordinator delegates to.
typedef ReconcilePromptCallback = Future<ReviewAction> Function(String prompt);
typedef ReviewHeroCallback = Future<ReviewAction> Function(dynamic hero, int current, int total);
typedef SnackBarCallback = void Function(String message);

/// Coordinates hero CRUD operations and filter orchestration.
///
/// Uses [HeroDataManaging] for DB operations and creates SHQL™ display objects
/// on the fly via [HeroShqlAdapter]. No Dart-side object cache — `Heroes.heroes`
/// in the SHQL™ runtime is the single source of truth for hero objects.
class HeroCoordinator {
  HeroCoordinator({
    required ShqlBindings shqlBindings,
    required HeroDataManaging heroDataManager,
    required HeroServicing? Function() heroServiceFactory,
    required FilterCompiler filterCompiler,
    required ReconcilePromptCallback showReconcileDialog,
    required ReviewHeroCallback showReviewHeroDialog,
    required SnackBarCallback showSnackBar,
    required VoidCallback onStateChanged,
    this.searchHeightConflictResolver,
    this.searchWeightConflictResolver,
  })  : _shqlBindings = shqlBindings,
        _heroDataManager = heroDataManager,
        _heroServiceFactory = heroServiceFactory,
        _filterCompiler = filterCompiler,
        _showReconcileDialog = showReconcileDialog,
        _showReviewHeroDialog = showReviewHeroDialog,
        _showSnackBar = showSnackBar,
        _onStateChanged = onStateChanged;

  final ShqlBindings _shqlBindings;
  final HeroDataManaging _heroDataManager;
  final HeroServicing? Function() _heroServiceFactory;
  final FilterCompiler _filterCompiler;
  final ReconcilePromptCallback _showReconcileDialog;
  final ReviewHeroCallback _showReviewHeroDialog;
  final SnackBarCallback _showSnackBar;
  final VoidCallback _onStateChanged;

  // Transient state for reconciliation timestamp.
  DateTime? _reconcileTimestamp;

  /// API response cache — same query on the same day returns cached JSON.
  final Map<String, Map<String, dynamic>> _searchCache = {};

  /// Creates a SHQL™ object from a HeroModel.
  dynamic _createHeroObject(HeroModel hero) =>
      HeroShqlAdapter.heroToShqlObject(hero, _shqlBindings.identifiers);

  // ---------------------------------------------------------------------------
  // Hero CRUD
  // ---------------------------------------------------------------------------

  /// _HERO_DELETE callback: deletes hero from DB.
  /// Returns true on success, null if hero not found.
  /// SHQL™ owns both objects and IDs — Dart just does the DB delete.
  dynamic heroDelete(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;
    _heroDataManager.delete(hero);
    return true;
  }

  /// _HERO_AMEND callback: apply an amendment map to a hero model, persist to DB.
  /// Returns {new_obj, id} for SHQL™ to update state, or null on failure.
  /// SHQL™ provides the old object from Heroes.heroes itself.
  Future<dynamic> heroAmend(String heroId, dynamic amendmentObj) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return null;
    }

    // Convert SHQL™ Object → Dart Map (recursively for nested sections)
    final amendment = _deepObjectToMap(amendmentObj);

    final amended = await hero.amendWith(amendment);
    _heroDataManager.persist(amended);
    final newObj = _createHeroObject(amended);

    _onStateChanged();

    return _shqlBindings.mapToObject({
      'new_obj': newObj,
      'id': amended.id,
    });
  }

  Map<String, dynamic> _deepObjectToMap(dynamic obj) {
    final Map<String, dynamic> map;
    if (_shqlBindings.isShqlObject(obj)) {
      map = _shqlBindings.objectToMap(obj);
    } else if (obj is Map) {
      map = obj.map((k, v) => MapEntry(k.toString(), v));
    } else {
      return {};
    }
    return map.map((key, value) =>
        MapEntry(key, (value is Map || _shqlBindings.isShqlObject(value))
            ? _deepObjectToMap(value) : value));
  }

  /// _HERO_TOGGLE_LOCK callback: toggles lock on hero model, persists to DB.
  /// Returns {locked: bool} or null if hero not found.
  dynamic heroToggleLock(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;
    final toggled = hero.locked ? hero.unlock() : hero.copyWith(locked: true);
    _heroDataManager.persist(toggled);
    return _shqlBindings.mapToObject({'locked': toggled.locked});
  }

  // ---------------------------------------------------------------------------
  // Reconciliation callbacks (called from SHQL™ RECONCILE_HEROES loop)
  // ---------------------------------------------------------------------------

  /// _INIT_RECONCILE callback: prepares for reconciliation loop.
  /// Returns true if ready, false if no heroes to reconcile.
  Future<bool> initReconcile() async {
    if (_heroDataManager.heroes.isEmpty) {
      _showSnackBar('No saved heroes to reconcile');
      return false;
    }
    _reconcileTimestamp = DateTime.timestamp();
    return true;
  }

  /// _RECONCILE_FETCH callback: fetches online data for a hero by ID,
  /// applies with auto-resolvers, diffs. Returns result OBJECT or null.
  Future<dynamic> reconcileFetch(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;
    final heroService = _heroServiceFactory();
    if (heroService == null) return null;

    final onlineJson = await heroService.getById(hero.externalId);
    String? error;
    if (onlineJson != null) error = onlineJson['error'] as String?;

    if (onlineJson == null || error != null) {
      return _shqlBindings.mapToObject({
        'found': false,
        'error': error ?? 'not found',
      });
    }

    final previousHeightResolver = Height.conflictResolver;
    final previousWeightResolver = Weight.conflictResolver;
    try {
      final heightResolver = Height.conflictResolver =
          AutoConflictResolver<Height>(hero.appearance.height.systemOfUnits);
      final weightResolver = Weight.conflictResolver =
          AutoConflictResolver<Weight>(hero.appearance.weight.systemOfUnits);

      HeroModel updatedHero;
      try {
        updatedHero = await hero.apply(onlineJson, _reconcileTimestamp!, false);
      } catch (e) {
        return _shqlBindings.mapToObject({
          'found': true,
          'apply_error': e.toString(),
        });
      }

      final resolutionLogs = <dynamic>[
        ...heightResolver.resolutionLog,
        ...weightResolver.resolutionLog,
      ];

      final sb = StringBuffer();
      final hasDiff = hero.diff(updatedHero, sb);

      return _shqlBindings.mapToObject({
        'found': true,
        'apply_error': null,
        'has_diff': hasDiff,
        'diff_text': sb.toString(),
        'resolution_logs': resolutionLogs,
        'conflict_count': resolutionLogs.length,
        'updated_hero': updatedHero,
      });
    } finally {
      Height.conflictResolver = previousHeightResolver;
      Weight.conflictResolver = previousWeightResolver;
    }
  }

  /// Persist a HeroModel to DB and return a SHQL™ Object.
  /// Used by _PERSIST_HERO callback (search and reconciliation).
  dynamic persistAndMap(dynamic hero) {
    if (hero is! HeroModel) return null;
    _heroDataManager.persist(hero);
    return _createHeroObject(hero);
  }

  /// Create SHQL™ Object without persisting (for display of skipped heroes).
  dynamic mapHero(dynamic hero) {
    if (hero is! HeroModel) return null;
    return _createHeroObject(hero);
  }

  /// _RECONCILE_PROMPT callback: shows reconcile dialog, returns action string.
  Future<String> reconcilePrompt(String text) async {
    final action = await _showReconcileDialog(text);
    return switch (action) {
      ReviewAction.save => 'save',
      ReviewAction.skip => 'skip',
      ReviewAction.saveAll => 'saveAll',
      ReviewAction.cancel => 'cancel',
    };
  }

  /// _FINISH_RECONCILE callback: cleans up transient Dart reconciliation state.
  /// SHQL™ handles the rebuild (FULL_REBUILD_AND_DISPLAY) itself after calling this.
  void finishReconcile() {
    _reconcileTimestamp = null;
  }

  /// Shows a snack bar message (exposed for SHQL™ _SHOW_SNACKBAR callback).
  void showSnackBar(String message) => _showSnackBar(message);

  /// _HERO_CLEAR callback: clear all hero data from the database.
  /// SHQL™ handles the state cleanup (ON_HERO_CLEAR) itself.
  void heroClear() {
    _heroDataManager.clear();
    _onStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  String _cacheKey(String query) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '${query.toLowerCase()}|$today';
  }

  void _pruneCache() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    _searchCache.removeWhere((key, _) => !key.endsWith(today));
  }

  /// _SEARCH_HEROES callback: API fetch + parse → opaque HeroModel list.
  /// Returns {success, results: [HeroModel...], error}.
  Future<dynamic> searchHeroes(String query) async {
    try {
      final heroService = _heroServiceFactory();
      if (heroService == null) {
        return _errorResult('No API credentials configured');
      }

      _pruneCache();
      final key = _cacheKey(query);
      var data = _searchCache[key];
      if (data == null) {
        data = await heroService.search(query);
        if (data != null && data['response'] == 'success') {
          _searchCache[key] = data;
        }
      }
      if (data == null || data['response'] != 'success') {
        return _errorResult(
          data?['error']?.toString() ?? 'No results found for "$query"',
        );
      }

      final previousHeightResolver = Height.conflictResolver;
      final previousWeightResolver = Weight.conflictResolver;
      if (searchHeightConflictResolver != null) {
        Height.conflictResolver = searchHeightConflictResolver!;
      }
      if (searchWeightConflictResolver != null) {
        Weight.conflictResolver = searchWeightConflictResolver!;
      }

      try {
        final failures = <String>[];
        final searchResponse = await SearchResponseModel.fromJson(
          _heroDataManager, data, DateTime.timestamp(), failures,
        );
        for (final f in failures) {
          debugPrint('Search parse failure: $f');
        }

        return _shqlBindings.mapToObject({
          'success': true,
          'results': searchResponse.results,
          'error': null,
        });
      } finally {
        Height.conflictResolver = previousHeightResolver;
        Weight.conflictResolver = previousWeightResolver;
      }
    } catch (e) {
      debugPrint('Search error: $e');
      return _errorResult('Search failed: $e');
    }
  }

  dynamic _errorResult(String message) => _shqlBindings.mapToObject({
    'success': false,
    'results': <dynamic>[],
    'error': message,
  });

  /// Returns the internal ID if this hero is already saved, null otherwise.
  dynamic getSavedId(dynamic hero) {
    if (hero is! HeroModel) return null;
    return _heroDataManager.getByExternalId(hero.externalId)?.id;
  }

  /// Shows review dialog for an opaque HeroModel. Returns action string.
  Future<String> reviewHero(dynamic hero, int current, int total) async {
    if (hero is! HeroModel) return 'skip';
    final action = await _showReviewHeroDialog(hero, current, total);
    return switch (action) {
      ReviewAction.save => 'save',
      ReviewAction.skip => 'skip',
      ReviewAction.saveAll => 'saveAll',
      ReviewAction.cancel => 'cancel',
    };
  }

  /// Conflict resolvers for height/weight parsing during search.
  /// Null in tests — search parsing uses default (first-provided-value) resolver.
  ConflictResolver<Height>? searchHeightConflictResolver;
  ConflictResolver<Weight>? searchWeightConflictResolver;

  // ---------------------------------------------------------------------------
  // Edit form preparation
  // ---------------------------------------------------------------------------

  static final Map<Type, List<Enum>> _enumRegistry = {
    Gender: Gender.values,
    bio.Alignment: bio.Alignment.values,
  };

  /// Dart primitive: build edit field descriptors from a hero's Field hierarchy.
  /// Returns a list of SHQL™ Objects, or null if hero not found.
  dynamic buildEditFields(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;

    final editFields = <dynamic>[];

    for (final fb in hero.fields) {
      final f = fb as Field;
      if (!f.mutable || f.assignedBySystem) continue;

      if (f.children.isNotEmpty && !f.childrenForDbOnly) {
        final subModel = (f as dynamic).getter(hero);
        if (subModel == null) continue;

        for (final cfb in f.children) {
          final cf = cfb as Field;
          if (!cf.mutable || cf.assignedBySystem) continue;

          final leafValue = (cf as dynamic).getter(subModel);
          String fieldType = 'string';
          List<dynamic> options = [];
          List<dynamic> enumNames = [];
          String displayValue;

          if (leafValue is Enum) {
            fieldType = 'enum';
            final allValues = _enumRegistry[leafValue.runtimeType];
            if (allValues != null) {
              options = allValues
                  .map((e) => (e as dynamic).displayName as String)
                  .toList();
              enumNames = allValues.map((e) => e.name).toList();
            }
            displayValue = leafValue.index < options.length
                ? options[leafValue.index] as String
                : leafValue.name;
          } else {
            displayValue = (cf as dynamic).format(subModel);
          }

          editFields.add(_shqlBindings.mapToObject({
            'section': f.name,
            'label': cf.name,
            'json_section': f.jsonName,
            'json_name': cf.jsonName,
            'value': displayValue,
            'original': displayValue,
            'field_type': fieldType,
            'options': options,
            'enum_names': enumNames,
          }));
        }
      } else {
        editFields.add(_shqlBindings.mapToObject({
          'section': '',
          'label': f.name,
          'json_section': '',
          'json_name': f.jsonName,
          'value': (f as dynamic).format(hero),
          'original': (f as dynamic).format(hero),
          'field_type': 'string',
          'options': [],
          'enum_names': [],
        }));
      }
    }

    return editFields;
  }

  // ---------------------------------------------------------------------------
  // Filter orchestration
  // ---------------------------------------------------------------------------

  /// Dart callback for _COMPILE_FILTERS — compiles predicates and publishes
  /// the lambda map to the SHQL™ runtime.
  Future<void> compileFilters() => _filterCompiler.compileAndPublish();

  /// Dart callback for _COMPILE_QUERY — compiles a single query expression
  /// into a SHQL™ lambda (predicate or text-match).
  Future<dynamic> compileQuery(String query) => _filterCompiler.compileQuery(query);

  /// Look up a HeroModel from an SHQL™ hero object and text-match against it.
  bool matchHeroObject(dynamic heroObj, String text) {
    final map = _shqlBindings.objectToMap(heroObj);
    final id = map['id'] as String?;
    if (id == null) return false;
    final hero = _heroDataManager.getById(id);
    if (hero == null) return false;
    return hero.matches(text);
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Full startup: loads all heroes from DB, adds them to SHQL™ state,
  /// compiles and rebuilds filters, populates card cache — one SHQL™ eval.
  /// Always compiles filters even with an empty DB so that filter lambdas
  /// are ready when the first hero is saved via search.
  Future<void> startup() async {
    final allHeroes = _heroDataManager.heroes;
    if (allHeroes.isEmpty) {
      await _shqlBindings.eval('Filters.FULL_REBUILD()');
      return;
    }
    final objects = HeroShqlAdapter.heroesToShqlList(
      allHeroes, _shqlBindings.identifiers,
    );
    await _shqlBindings.eval('Heroes.STARTUP(__list)',
        boundValues: {'__list': objects});
  }

}
