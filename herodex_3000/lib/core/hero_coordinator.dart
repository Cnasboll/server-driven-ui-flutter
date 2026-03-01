import 'package:flutter/foundation.dart';
import 'package:hero_common/env/env.dart';
import 'package:hero_common/managers/hero_data_managing.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/services/hero_service.dart';
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
    required FilterCompiler filterCompiler,
    required ReconcilePromptCallback showReconcileDialog,
    required SnackBarCallback showSnackBar,
    required VoidCallback onStateChanged,
  })  : _shqlBindings = shqlBindings,
        _heroDataManager = heroDataManager,
        _filterCompiler = filterCompiler,
        _showReconcileDialog = showReconcileDialog,
        _showSnackBar = showSnackBar,
        _onStateChanged = onStateChanged;

  final ShqlBindings _shqlBindings;
  final HeroDataManaging _heroDataManager;
  final FilterCompiler _filterCompiler;
  final ReconcilePromptCallback _showReconcileDialog;
  final SnackBarCallback _showSnackBar;
  final VoidCallback _onStateChanged;

  // Public access to the data manager (for search service)
  HeroDataManaging get heroDataManager => _heroDataManager;

  // Transient state for reconciliation — stores the HeroService for the
  // duration of the reconciliation loop. Updated HeroModels are returned as
  // opaque values in the fetch result — SHQL holds them and passes to persist.
  HeroService? _reconcileService;
  DateTime? _reconcileTimestamp;

  /// Creates a SHQL™ object from a HeroModel.
  dynamic _createHeroObject(HeroModel hero) =>
      HeroShqlAdapter.heroToShqlObject(hero, _shqlBindings.identifiers);

  // ---------------------------------------------------------------------------
  // Hero CRUD
  // ---------------------------------------------------------------------------

  /// Persist a hero to DB, create SHQL object, let SHQL handle old lookup + state — single eval.
  Future<void> persistHero(HeroModel hero) async {
    _heroDataManager.persist(hero);
    final newObj = _createHeroObject(hero);

    await _shqlBindings.eval(
      'Heroes.PERSIST_AND_REBUILD(__new)',
      boundValues: {'__new': newObj},
    );
    _onStateChanged();
  }

  /// _HERO_DATA_DELETE callback: deletes hero from DB.
  /// Returns true on success, null if hero not found.
  /// SHQL owns both objects and IDs — Dart just does the DB delete.
  dynamic heroDataDelete(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;
    _heroDataManager.delete(hero);
    return true;
  }

  /// Dart primitive: apply an amendment map to a hero model, persist to DB.
  /// Returns {new_obj, id} for SHQL to update state, or null on failure.
  /// SHQL provides the old object from Heroes.heroes itself.
  Future<dynamic> heroDataAmend(String heroId, dynamic amendmentObj) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return null;
    }

    // Convert SHQL Object → Dart Map (recursively for nested sections)
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
    final map = _shqlBindings.objectToMap(obj);
    return map.map((key, value) =>
        MapEntry(key, _shqlBindings.isShqlObject(value) ? _deepObjectToMap(value) : value));
  }

  /// _HERO_DATA_TOGGLE_LOCK callback: toggles lock on hero model, persists to DB.
  /// Returns {locked: bool} or null if hero not found.
  dynamic heroDataToggleLock(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;
    final toggled = hero.locked ? hero.unlock() : hero.copyWith(locked: true);
    _heroDataManager.persist(toggled);
    return _shqlBindings.mapToObject({'locked': toggled.locked});
  }

  // ---------------------------------------------------------------------------
  // Reconciliation callbacks (called from SHQL™ RECONCILE_HEROES loop)
  // ---------------------------------------------------------------------------

  /// _INIT_RECONCILE callback: acquires HeroService (may prompt for API key).
  /// Returns true if ready, false/null if no service.
  Future<bool> initReconcile() async {
    if (_heroDataManager.heroes.isEmpty) {
      _showSnackBar('No saved heroes to reconcile');
      return false;
    }
    _reconcileService = await getHeroService();
    if (_reconcileService == null) return false;
    _reconcileTimestamp = DateTime.timestamp();
    return true;
  }

  /// _RECONCILE_FETCH callback: fetches online data for a hero by ID,
  /// applies with auto-resolvers, diffs. Returns result OBJECT or null.
  Future<dynamic> reconcileFetch(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null || _reconcileService == null) return null;

    final onlineJson = await _reconcileService!.getById(hero.externalId);
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

  /// _RECONCILE_PERSIST callback: takes opaque HeroModel from SHQL, persists
  /// to DB, returns SHQL Object. Same pattern as _SAVE_HERO in search.
  dynamic reconcilePersist(dynamic hero) {
    if (hero is! HeroModel) return null;
    _heroDataManager.persist(hero);
    return _createHeroObject(hero);
  }

  /// _RECONCILE_DELETE callback: deletes a hero by ID from the DB.
  /// SHQL provides the old object from Heroes.heroes for state cleanup.
  void reconcileDelete(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero != null) _heroDataManager.delete(hero);
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
  /// SHQL handles the rebuild (FULL_REBUILD_AND_DISPLAY) itself after calling this.
  void finishReconcile() {
    _reconcileService = null;
    _reconcileTimestamp = null;
  }

  /// Shows a snack bar message (exposed for SHQL™ _SHOW_SNACKBAR callback).
  void showSnackBar(String message) => _showSnackBar(message);

  /// Dart primitive: clear all hero data from the database.
  /// SHQL handles the state cleanup (ON_HERO_CLEAR) itself.
  void heroDataClear() {
    _heroDataManager.clear();
    _onStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Edit form preparation
  // ---------------------------------------------------------------------------

  static final Map<Type, List<Enum>> _enumRegistry = {
    Gender: Gender.values,
    bio.Alignment: bio.Alignment.values,
  };

  /// Dart primitive: build edit field descriptors from a hero's Field hierarchy.
  /// Returns a list of SHQL Objects, or null if hero not found.
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

  /// Full rebuild: delegates to SHQL™ FULL_REBUILD which handles the
  /// compile→rebuild→display pipeline, then rebuilds hero cards from cache.
  Future<void> rebuildAllFilters() async {
    await _shqlBindings.eval('Heroes.FULL_REBUILD_AND_DISPLAY()');
  }

  // ---------------------------------------------------------------------------
  // Hero service
  // ---------------------------------------------------------------------------

  Future<HeroService?> getHeroService() async {
    final result = await _shqlBindings.eval('Prefs.GET_API_CREDENTIALS()');
    if (result == null) return null;
    final creds = _shqlBindings.objectToMap(result);
    return HeroService(Env.create(
      apiKey: creds['api_key'].toString(),
      apiHost: creds['api_host'].toString(),
    ));
  }

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

  /// Loads all heroes from DB, creates SHQL™ display objects, and pushes them
  /// into the SHQL™ runtime via Heroes.ON_HEROES_ADDED.
  Future<void> initializeHeroes() async {
    final allHeroes = _heroDataManager.heroes;
    if (allHeroes.isNotEmpty) {
      final objects = HeroShqlAdapter.heroesToShqlList(
        allHeroes, _shqlBindings.identifiers,
      );
      await _shqlBindings.eval('Heroes.ON_HEROES_ADDED(__list)',
          boundValues: {'__list': objects});
    }
  }

  /// Populates the SHQL™ card cache for all saved heroes and rebuilds
  /// `hero_cards`. Call after initializeHeroes() + rebuildAllFilters() at startup.
  /// Single eval — no per-hero loop from Dart.
  Future<void> populateHeroCardCache() async {
    final allHeroes = _heroDataManager.heroes;
    if (allHeroes.isEmpty) return;
    final objects = HeroShqlAdapter.heroesToShqlList(
      allHeroes, _shqlBindings.identifiers,
    );
    await _shqlBindings.eval(
      'Cards.CLEAR_CARD_CACHE(); Cards.CACHE_HERO_CARDS(__list); Heroes.REBUILD_CARDS()',
      boundValues: {'__list': objects},
    );
  }

}
