import 'package:flutter/foundation.dart';
import 'package:hero_common/env/env.dart';
import 'package:hero_common/models/hero_model.dart';
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
import '../persistence/shql_hero_data_manager.dart';

/// Callback typedefs for UI interactions that the coordinator delegates to.
typedef ReconcilePromptCallback = Future<ReviewAction> Function(String prompt);
typedef SnackBarCallback = void Function(String message);

/// Coordinates hero CRUD operations and filter orchestration.
///
/// Owns [ShqlHeroDataManager] and [FilterCompiler]. main.dart creates this
/// after ShqlBindings + data manager + filter compiler are initialized, and
/// wires SHQL™ callbacks to its methods.
class HeroCoordinator {
  HeroCoordinator({
    required ShqlBindings shqlBindings,
    required ShqlHeroDataManager heroDataManager,
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
  final ShqlHeroDataManager _heroDataManager;
  final FilterCompiler _filterCompiler;
  final ReconcilePromptCallback _showReconcileDialog;
  final SnackBarCallback _showSnackBar;
  final VoidCallback _onStateChanged;

  // Public access to the data manager (for search service and main.dart wiring)
  ShqlHeroDataManager get heroDataManager => _heroDataManager;

  // Transient state for reconciliation — stores the HeroService and pending
  // updated hero between _RECONCILE_FETCH and _RECONCILE_PERSIST callbacks.
  HeroService? _reconcileService;
  HeroModel? _reconcilePendingHero;
  DateTime? _reconcileTimestamp;

  // ---------------------------------------------------------------------------
  // Hero CRUD
  // ---------------------------------------------------------------------------

  /// Persist a hero. Updates SHQL™ state, caches card, rebuilds display — single eval.
  Future<void> persistHero(HeroModel hero) async {
    final oldObj = _heroDataManager.getHeroObject(hero.id);
    _heroDataManager.persist(hero);
    final newObj = _heroDataManager.getHeroObject(hero.id)!;

    await _shqlBindings.eval(
      'Heroes.ON_HERO_PERSISTED(__old, __new); Cards.CACHE_HERO_CARD(__new); Heroes.REBUILD_CARDS()',
      boundValues: {'__old': oldObj, '__new': newObj},
    );
    _onStateChanged();
  }

  Future<void> deleteHero(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return;
    }

    // Fast path: remove card + displayed entry immediately for snappy UX,
    // before the slower O(filters) cleanup in ON_HERO_DELETED.
    await _shqlBindings.eval(
      'Cards.REMOVE_CACHED_CARD(__id); Filters.REMOVE_FROM_DISPLAYED(__id); Heroes.REBUILD_CARDS()',
      boundValues: {'__id': heroId},
    );

    final oldObj = _heroDataManager.getHeroObject(heroId);
    _heroDataManager.delete(hero);

    if (oldObj != null) {
      await _shqlBindings.eval(
        'Heroes.ON_HERO_DELETED(__hero, __eid); Heroes.REBUILD_CARDS()',
        boundValues: {'__hero': oldObj, '__eid': hero.externalId},
      );
    }
    _onStateChanged();
  }

  Future<void> amendHero(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return;
    }

    // SHQL™ builds the amendment map from edit_fields (Rule 1: no Dart logic on SHQL data)
    final amendmentObj = await _shqlBindings.eval('HeroEdit.BUILD_AMENDMENT()');
    if (amendmentObj == null) {
      _showSnackBar('No changes made');
      return;
    }

    // Convert SHQL Object → Dart Map (recursively for nested sections)
    final amendment = _deepObjectToMap(amendmentObj);

    final oldObj = _heroDataManager.getHeroObject(hero.id);
    final amended = await hero.amendWith(amendment);
    _heroDataManager.persist(amended);
    final newObj = _heroDataManager.getHeroObject(amended.id)!;

    await _shqlBindings.eval(
      'Heroes.ON_HERO_PERSISTED(__old, __new); Cards.CACHE_HERO_CARD(__new); Heroes.REBUILD_CARDS(); Heroes.FINISH_AMEND(__id)',
      boundValues: {'__old': oldObj, '__new': newObj, '__id': amended.id},
    );

    _onStateChanged();
    _showSnackBar('Hero amended (locked from reconciliation)');
  }

  Map<String, dynamic> _deepObjectToMap(dynamic obj) {
    final map = _shqlBindings.objectToMap(obj);
    return map.map((key, value) =>
        MapEntry(key, _shqlBindings.isShqlObject(value) ? _deepObjectToMap(value) : value));
  }

  Future<void> toggleLock(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return;
    }

    final toggled = hero.locked ? hero.unlock() : hero.copyWith(locked: true);
    _heroDataManager.persist(toggled);

    // Toggle lock, re-cache card from updated heroes map entry, rebuild display.
    await _shqlBindings.eval(
      'Heroes.TOGGLE_LOCK(__id, __locked); Cards.CACHE_HERO_CARD(Heroes.heroes[__id]); Heroes.REBUILD_CARDS()',
      boundValues: {'__id': toggled.id, '__locked': toggled.locked},
    );

    _showSnackBar(toggled.locked
        ? 'Hero locked — reconciliation skipped'
        : 'Hero unlocked — reconciliation enabled');
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

      _reconcilePendingHero = updatedHero;

      return _shqlBindings.mapToObject({
        'found': true,
        'has_diff': hasDiff,
        'diff_text': sb.toString(),
        'resolution_logs': resolutionLogs,
        'conflict_count': resolutionLogs.length,
      });
    } finally {
      Height.conflictResolver = previousHeightResolver;
      Weight.conflictResolver = previousWeightResolver;
    }
  }

  /// _RECONCILE_PERSIST callback: persists the pending updated hero.
  /// Returns OBJECT{old_obj, new_obj}. SHQL handles card caching.
  Future<dynamic> reconcilePersist(String heroId) async {
    final pending = _reconcilePendingHero;
    if (pending == null) return null;

    final oldObj = _heroDataManager.getHeroObject(heroId);
    _heroDataManager.persist(pending);
    final newObj = _heroDataManager.getHeroObject(pending.id)!;
    _reconcilePendingHero = null;

    return _shqlBindings.mapToObject({
      'old_obj': oldObj,
      'new_obj': newObj,
    });
  }

  /// _RECONCILE_DELETE callback: deletes a hero by ID.
  /// Returns the old SHQL™ object for SHQL™ ON_HERO_REMOVED.
  /// SHQL handles card cache removal.
  dynamic reconcileDelete(String heroId) {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return null;
    final oldObj = _heroDataManager.getHeroObject(heroId);
    _heroDataManager.delete(hero);
    return oldObj;
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

  /// _FINISH_RECONCILE callback: rebuilds filters and cards after reconciliation.
  Future<void> finishReconcile() async {
    _reconcileService = null;
    _reconcilePendingHero = null;
    _reconcileTimestamp = null;
    await _shqlBindings.eval('Filters.FULL_REBUILD(); Heroes.REBUILD_CARDS()');
    _onStateChanged();
  }

  /// Shows a snack bar message (exposed for SHQL™ _SHOW_SNACKBAR callback).
  void showSnackBar(String message) => _showSnackBar(message);

  Future<void> clearData() async {
    _heroDataManager.clear();
    await _shqlBindings.eval('Heroes.ON_HERO_CLEAR()');
    _onStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Edit form preparation
  // ---------------------------------------------------------------------------

  static final Map<Type, List<Enum>> _enumRegistry = {
    Gender: Gender.values,
    bio.Alignment: bio.Alignment.values,
  };

  Future<void> prepareEdit() async {
    final heroObj = await _shqlBindings.eval('Heroes.selected_hero');
    if (heroObj == null) return;
    final heroMap = _shqlBindings.objectToMap(heroObj);
    final heroId = heroMap['id'] as String?;
    if (heroId == null) return;
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) return;

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

    // Set the object member AND notify via the setter method on HeroEdit.
    await _shqlBindings.eval(
      'HeroEdit.SET_EDIT_FIELDS(__fields)',
      boundValues: {'__fields': editFields},
    );
  }

  // ---------------------------------------------------------------------------
  // Filter orchestration
  // ---------------------------------------------------------------------------

  /// Called when `_filters` SHQL™ variable changes.
  /// SHQL™ FULL_REBUILD handles: SET_IS_COMPILING, _COMPILE_FILTERS callback,
  /// REBUILD_ALL_FILTERS, SET_IS_COMPILING(FALSE). Then REBUILD_CARDS reindexes.
  Future<void> onFiltersChanged() async {
    await _shqlBindings.eval('Filters.FULL_REBUILD(); Heroes.REBUILD_CARDS()');
    _onStateChanged();
  }

  /// Dart callback for _COMPILE_FILTERS — compiles predicates and publishes
  /// the lambda map to the SHQL™ runtime.
  Future<void> compileFilters() => _filterCompiler.compileAndPublish();

  /// Dart callback for _COMPILE_QUERY — compiles a single query expression
  /// into a SHQL™ lambda (predicate or text-match).
  Future<dynamic> compileQuery(String query) => _filterCompiler.compileQuery(query);

  /// Full rebuild: delegates to SHQL™ FULL_REBUILD which handles the
  /// compile→rebuild→display pipeline, then rebuilds hero cards from cache.
  Future<void> rebuildAllFilters() async {
    await _shqlBindings.eval('Filters.FULL_REBUILD(); Heroes.REBUILD_CARDS()');
  }

  /// Called when `_current_query` changes. SHQL™ ON_QUERY_CHANGED handles:
  /// trim, empty check, IS_FILTERING bookends, _COMPILE_QUERY callback,
  /// FILTER_DISPLAYED/UPDATE_DISPLAYED_HEROES. Then REBUILD_CARDS reindexes.
  Future<void> onQueryChanged() async {
    await _shqlBindings.eval('Filters.ON_QUERY_CHANGED(); Heroes.REBUILD_CARDS()');
    _onStateChanged();
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
  // Helpers
  // ---------------------------------------------------------------------------

  /// Populates the SHQL™ card cache for all saved heroes and rebuilds
  /// `hero_cards`. Call after initialize() + rebuildAllFilters() at startup.
  ///
  /// [onProgress] is called before each hero is cached with (current, total, heroName).
  Future<void> populateHeroCardCache({
    void Function(int current, int total, String heroName)? onProgress,
  }) async {
    await _shqlBindings.eval('Cards.CLEAR_CARD_CACHE()');
    final entries = _heroDataManager.heroObjectsById.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final heroName = _heroDataManager.getById(entry.key)?.name ?? '';
      onProgress?.call(i + 1, entries.length, heroName);
      await _shqlBindings.eval('Cards.CACHE_HERO_CARD(__hero)',
          boundValues: {'__hero': entry.value});
    }
    await _shqlBindings.eval('Heroes.REBUILD_CARDS()');
  }

  /// Called when `Filters.displayed_heroes` changes (from any source — Dart or SHQL™).
  void onDisplayedHeroesChanged() {
    _shqlBindings.eval('Heroes.REBUILD_CARDS()');
  }
}
