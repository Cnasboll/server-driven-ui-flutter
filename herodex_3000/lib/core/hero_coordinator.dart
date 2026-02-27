import 'package:flutter/foundation.dart';
import 'package:hero_common/env/env.dart';
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
import '../persistence/shql_hero_data_manager.dart';

/// Callback typedefs for UI interactions that the coordinator delegates to.
typedef PromptCallback = Future<String> Function(String prompt, [String defaultValue]);
typedef ConfirmCallback = Future<bool> Function(String prompt);
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
    required PromptCallback showPromptDialog,
    required ReconcilePromptCallback showReconcileDialog,
    required SnackBarCallback showSnackBar,
    required VoidCallback onStateChanged,
  })  : _shqlBindings = shqlBindings,
        _heroDataManager = heroDataManager,
        _filterCompiler = filterCompiler,
        _showPromptDialog = showPromptDialog,
        _showReconcileDialog = showReconcileDialog,
        _showSnackBar = showSnackBar,
        _onStateChanged = onStateChanged;

  final ShqlBindings _shqlBindings;
  final ShqlHeroDataManager _heroDataManager;
  final FilterCompiler _filterCompiler;
  final PromptCallback _showPromptDialog;
  final ReconcilePromptCallback _showReconcileDialog;
  final SnackBarCallback _showSnackBar;
  final VoidCallback _onStateChanged;

  // Public access to the data manager (for search service and main.dart wiring)
  ShqlHeroDataManager get heroDataManager => _heroDataManager;

  // Per-ID cache of pre-built hero card widget descriptions.
  // Only regenerated when a hero's data changes (persist/amend/unlock/reconcile).
  // Filter and query changes just reindex from the cache — no SHQL™ eval needed.
  final Map<String, dynamic> _heroCardCache = {};

  // ---------------------------------------------------------------------------
  // Hero CRUD
  // ---------------------------------------------------------------------------

  /// Persist a hero. ON_HERO_ADDED/REPLACED updates the heroes map, running
  /// stats, and filter membership in one SHQL™ call. O(filters).
  Future<void> persistHero(HeroModel hero) async {
    final oldObj = _heroDataManager.getHeroObject(hero.id);
    _heroDataManager.persist(hero);
    final newObj = _heroDataManager.getHeroObject(hero.id)!;

    if (oldObj != null) {
      await _shqlBindings.eval(
        'ON_HERO_REPLACED(__old, __new)',
        boundValues: {'__old': oldObj, '__new': newObj},
      );
    } else {
      await _shqlBindings.eval(
        'ON_HERO_ADDED(__hero)',
        boundValues: {'__hero': newObj},
      );
    }

    await _cacheHeroCard(hero.id, newObj);
    await _updateDisplayedHeroes();
    _onStateChanged();
  }

  Future<void> deleteHero(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return;
    }

    // Immediately remove from cache and displayed list so the card disappears
    // at once, before the slower SHQL™ cleanup (ON_HERO_REMOVED iterates all filter maps).
    _removeHeroFromCache(heroId);
    final currentDisplayed = _shqlBindings.getVariable('_displayed_heroes');
    if (currentDisplayed is List) {
      final newDisplayed = currentDisplayed.where((h) {
        if (_shqlBindings.isShqlObject(h)) {
          return _shqlBindings.objectToMap(h)['id'] != heroId;
        }
        return true;
      }).toList();
      _setAndNotify('_displayed_heroes', newDisplayed);
    }
    _rebuildHeroCards();

    final oldObj = _heroDataManager.getHeroObject(heroId);
    _heroDataManager.delete(hero);

    if (oldObj != null) {
      await _shqlBindings.eval(
        'ON_HERO_REMOVED(__hero)',
        boundValues: {'__hero': oldObj},
      );
    }

    await _updateDisplayedHeroes();

    // Update selected hero if it matches
    try {
      final selectedEid = await _shqlBindings.eval(
        'IF _selected_hero != null THEN _selected_hero.external_id ELSE null',
      );
      if (selectedEid == hero.externalId) {
        _setAndNotify('_selected_hero',
          HeroShqlAdapter.heroToDisplayObject(hero, _shqlBindings.identifiers, isSaved: false),
        );
      }
    } catch (_) {}

    _onStateChanged();
  }

  Future<void> amendHero(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return;
    }

    final editFields = _shqlBindings.getVariable('_edit_fields');
    if (editFields is! List || editFields.isEmpty) {
      _showSnackBar('No edit data available');
      return;
    }

    final amendment = <String, dynamic>{};

    for (final fieldObj in editFields) {
      final fld = _shqlBindings.objectToMap(fieldObj);
      final value = fld['value']?.toString() ?? '';
      final original = fld['original']?.toString() ?? '';
      final jsonSection = fld['json_section']?.toString() ?? '';
      final jsonName = fld['json_name']?.toString() ?? '';
      final fieldType = fld['field_type']?.toString() ?? 'string';

      if (value == original) continue;

      String amendmentValue;
      if (fieldType == 'enum') {
        final options = fld['options'];
        final names = fld['enum_names'];
        if (options is List && names is List) {
          final index = options.indexOf(value);
          amendmentValue = (index >= 0 && index < names.length)
              ? names[index].toString()
              : value;
        } else {
          amendmentValue = value;
        }
      } else {
        amendmentValue = value;
      }

      if (jsonSection.isNotEmpty) {
        final section = amendment.putIfAbsent(
          jsonSection,
          () => <String, dynamic>{},
        ) as Map<String, dynamic>;
        section[jsonName] = amendmentValue;
      } else {
        amendment[jsonName] = amendmentValue;
      }
    }

    if (amendment.isEmpty) {
      _showSnackBar('No changes made');
      return;
    }

    final oldObj = _heroDataManager.getHeroObject(hero.id);
    final amended = await hero.amendWith(amendment);
    _heroDataManager.persist(amended);
    final newObj = _heroDataManager.getHeroObject(amended.id)!;

    if (oldObj != null) {
      await _shqlBindings.eval(
        'ON_HERO_REPLACED(__old, __new)',
        boundValues: {'__old': oldObj, '__new': newObj},
      );
    } else {
      await _shqlBindings.eval(
        'ON_HERO_ADDED(__hero)',
        boundValues: {'__hero': newObj},
      );
    }

    await _cacheHeroCard(amended.id, newObj);
    await _updateDisplayedHeroes();

    _setAndNotify(
      '_selected_hero',
      HeroShqlAdapter.heroToDisplayObject(
        amended,
        _shqlBindings.identifiers,
        isSaved: true,
      ),
    );

    _onStateChanged();
    _showSnackBar('Hero amended (locked from reconciliation)');

    await _shqlBindings.eval("GO_BACK()");
  }

  Future<void> toggleLock(String heroId) async {
    final hero = _heroDataManager.getById(heroId);
    if (hero == null) {
      debugPrint('Hero not found for id: $heroId');
      return;
    }

    final toggled = hero.locked ? hero.unlock() : hero.copyWith(locked: true);
    _heroDataManager.persist(toggled);
    final newObj = _heroDataManager.getHeroObject(toggled.id)!;

    // Lock toggle only flips a boolean — no filter/stats changes needed.
    // Update the SHQL™ _heroes map in-place and re-cache the card.
    await _shqlBindings.eval(
      "_heroes['${toggled.id}'].LOCKED := ${toggled.locked ? 'TRUE' : 'FALSE'}",
    );
    // Update _selected_hero so the detail page Observer refreshes the lock icon
    await _shqlBindings.eval(
      'IF _selected_hero <> null AND _selected_hero.ID = __id THEN BEGIN '
      '_selected_hero.LOCKED := __locked; SET("_selected_hero", _selected_hero); END',
      boundValues: {'__id': toggled.id, '__locked': toggled.locked},
    );
    await _cacheHeroCard(toggled.id, newObj);
    _rebuildHeroCards();

    _showSnackBar(toggled.locked
        ? 'Hero locked — reconciliation skipped'
        : 'Hero unlocked — reconciliation enabled');
  }

  Future<void> reconcile() async {
    final heroes = _heroDataManager.heroes;
    if (heroes.isEmpty) {
      _showSnackBar('No saved heroes to reconcile');
      return;
    }

    final heroService = await getHeroService();
    if (heroService == null) return;

    final timestamp = DateTime.timestamp();
    int updatedCount = 0;
    int deletionCount = 0;
    int lockedSkipCount = 0;
    int unchangedCount = 0;
    int conflictCount = 0;

    _setAndNotify('_reconcile_active', true);
    _setAndNotify('_reconcile_aborted', false);
    _setAndNotify('_reconcile_log', <dynamic>[]);

    bool acceptAllDeletes = false;
    bool acceptAllUpdates = false;
    bool aborted = false;

    try {
      for (final hero in heroes) {
        if (aborted || _shqlBindings.getVariable('_reconcile_aborted') == true) {
          _appendReconcileLog('— Reconciliation aborted by user —', isHeader: true);
          break;
        }

        _setAndNotify('_reconcile_current', hero.name);
        _setAndNotify('_reconcile_status', 'Fetching from online...');

        final onlineJson = await heroService.getById(hero.externalId);
        String? error;
        if (onlineJson != null) error = onlineJson['error'] as String?;

        if (onlineJson == null || error != null) {
          if (hero.locked) {
            _setAndNotify('_reconcile_status', 'Locked — skipping (not found online)');
            _appendReconcileLog('${hero.name}: not found online but locked — skipping', isWarning: true);
            lockedSkipCount++;
            continue;
          }
          bool shouldDelete = acceptAllDeletes;
          if (!acceptAllDeletes) {
            _setAndNotify('_reconcile_status', 'Not found online — prompting for deletion');
            final action = await _showReconcileDialog(
              'Hero "${hero.name}" no longer exists online (${error ?? "not found"}). Delete from local database?',
            );
            switch (action) {
              case ReviewAction.save: shouldDelete = true;
              case ReviewAction.skip: shouldDelete = false;
              case ReviewAction.saveAll: shouldDelete = true; acceptAllDeletes = true;
              case ReviewAction.cancel: aborted = true; continue;
            }
          }
          if (shouldDelete) {
            _setAndNotify('_reconcile_status', 'Deleted');
            final oldObj = _heroDataManager.getHeroObject(hero.id);
            _removeHeroFromCache(hero.id);
            _heroDataManager.delete(hero);
            if (oldObj != null) {
              await _shqlBindings.eval(
                'ON_HERO_REMOVED(__hero)',
                boundValues: {'__hero': oldObj},
              );
            }
            _appendReconcileLog('${hero.name}: deleted (no longer online)');
            deletionCount++;
          } else {
            _setAndNotify('_reconcile_status', 'Kept — skipped by user');
          }
          continue;
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
            updatedHero = await hero.apply(onlineJson, timestamp, false);
          } catch (e) {
            _setAndNotify('_reconcile_status', 'Error: $e');
            _appendReconcileLog('${hero.name}: error — $e', isWarning: true);
            continue;
          }

          final allResolutionLogs = [
            ...heightResolver.resolutionLog,
            ...weightResolver.resolutionLog,
          ];
          for (final msg in allResolutionLogs) {
            _appendReconcileLog('${hero.name}: $msg', isWarning: true);
            conflictCount++;
          }
          if (allResolutionLogs.isNotEmpty) {
            _setAndNotify('_reconcile_status',
              'Resolved ${allResolutionLogs.length} unit conflict(s)');
          }

          final sb = StringBuffer();
          final hasDiff = hero.diff(updatedHero, sb);
          if (!hasDiff) {
            _setAndNotify('_reconcile_status', 'Up to date — no changes');
            unchangedCount++;
            continue;
          }

          if (hero.locked) {
            _setAndNotify('_reconcile_status', 'Locked — skipping changes');
            _appendReconcileLog('${hero.name} (locked) — skipped:\n$sb', isWarning: true);
            lockedSkipCount++;
            continue;
          }

          bool shouldUpdate = acceptAllUpdates;
          if (!acceptAllUpdates) {
            final conflictNotes = allResolutionLogs.isNotEmpty
                ? '\n\nUnit conflict resolutions:\n${allResolutionLogs.join('\n')}'
                : '';
            _setAndNotify('_reconcile_status', 'Changes found — prompting to update');
            final action = await _showReconcileDialog(
              'Update "${hero.name}" with online changes?\n\n$sb$conflictNotes',
            );
            switch (action) {
              case ReviewAction.save: shouldUpdate = true;
              case ReviewAction.skip: shouldUpdate = false;
              case ReviewAction.saveAll: shouldUpdate = true; acceptAllUpdates = true;
              case ReviewAction.cancel: aborted = true; continue;
            }
          }
          if (shouldUpdate) {
            _setAndNotify('_reconcile_status', 'Updated');
            final oldObj = _heroDataManager.getHeroObject(hero.id);
            _heroDataManager.persist(updatedHero);
            final newObj = _heroDataManager.getHeroObject(updatedHero.id)!;
            if (oldObj != null) {
              await _shqlBindings.eval(
                'ON_HERO_REPLACED(__old, __new)',
                boundValues: {'__old': oldObj, '__new': newObj},
              );
            }
            await _cacheHeroCard(updatedHero.id, newObj);
            _appendReconcileLog('${hero.name}: updated');
            updatedCount++;
          } else {
            _setAndNotify('_reconcile_status', 'Skipped by user');
          }
        } finally {
          Height.conflictResolver = previousHeightResolver;
          Weight.conflictResolver = previousWeightResolver;
        }
      }
    } finally {
      _setAndNotify('_reconcile_active', false);
      _setAndNotify('_reconcile_aborted', false);
      _setAndNotify('_reconcile_current', '');
      _setAndNotify('_reconcile_status', '');
    }
    await _filterCompiler.compileAndPublish();
    await _shqlBindings.eval('REBUILD_ALL_FILTERS()');
    await _updateDisplayedHeroes();
    _onStateChanged();

    final parts = <String>[
      '$updatedCount updated',
      '$unchangedCount unchanged',
      if (deletionCount > 0) '$deletionCount deleted',
      if (lockedSkipCount > 0) '$lockedSkipCount locked (skipped)',
      if (conflictCount > 0) '$conflictCount unit conflict(s)',
    ];
    _appendReconcileLog('Done: ${parts.join(', ')}', isHeader: true);
    _showSnackBar('Reconciliation complete: ${parts.join(', ')}');
  }

  /// Appends a styled log entry to `_reconcile_log` for live display.
  void _appendReconcileLog(String message, {bool isHeader = false, bool isWarning = false}) {
    final current = (_shqlBindings.getVariable('_reconcile_log') as List?) ?? [];
    final color = isHeader ? '0xFF1976D2' : (isWarning ? '0xFFE65100' : '0xFF212121');
    final entry = {
      'type': 'Padding',
      'props': {
        'padding': {'left': 12.0, 'right': 12.0, 'top': 4.0, 'bottom': 4.0},
        'child': {
          'type': 'Text',
          'props': {
            'data': message,
            'style': {
              'fontSize': 12.0,
              'fontWeight': isHeader ? 'bold' : 'normal',
              'color': color,
            },
          },
        },
      },
    };
    _setAndNotify('_reconcile_log', [...current, entry]);
  }

  Future<void> clearData() async {
    _heroCardCache.clear();
    _heroDataManager.clear();
    await _shqlBindings.eval('ON_HERO_CLEAR()');
    await _updateDisplayedHeroes();
    _onStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Edit form preparation
  // ---------------------------------------------------------------------------

  static final Map<Type, List<Enum>> _enumRegistry = {
    Gender: Gender.values,
    bio.Alignment: bio.Alignment.values,
  };

  void prepareEdit() {
    final heroObj = _shqlBindings.getVariable('_selected_hero');
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

    _shqlBindings.setVariable('_edit_fields', editFields);
  }

  // ---------------------------------------------------------------------------
  // Filter orchestration
  // ---------------------------------------------------------------------------

  /// Called when `_filters` SHQL™ variable changes.
  /// Recompiles predicates and rebuilds all filter result maps in SHQL™.
  Future<void> onFiltersChanged() async {
    _setAndNotify('_filters_compiling', true);
    try {
      await _filterCompiler.compileAndPublish();
      await _shqlBindings.eval('REBUILD_ALL_FILTERS()');
      await _updateDisplayedHeroes();
      _onStateChanged();
    } finally {
      _setAndNotify('_filters_compiling', false);
    }
  }

  /// Full rebuild: compile predicates, rebuild filter maps, update display.
  /// Used after initial load.
  Future<void> rebuildAllFilters() async {
    _setAndNotify('_filters_compiling', true);
    try {
      await _filterCompiler.compileAndPublish();
      await _shqlBindings.eval('REBUILD_ALL_FILTERS()');
      await _updateDisplayedHeroes();
    } finally {
      _setAndNotify('_filters_compiling', false);
    }
  }

  /// Called when `_current_query` changes. Evaluates the compiled predicate
  /// against `_heroes` in SHQL™ and updates `_displayed_heroes`.
  ///
  /// [FilterCompiler.compileQuery] handles the dispatch:
  ///   • Semantically valid SHQL™ (e.g. `hero.powerstats.strength > 80`) → predicate lambda.
  ///   • Semantically invalid (e.g. "batman" — undefined identifier throws at eval) →
  ///     [isValidPredicate] catches that, falls back to MATCH(hero, text) text-search lambda.
  Future<void> onQueryChanged() async {
    final query = (_shqlBindings.getVariable('_current_query') ?? '').toString().trim();
    if (query.isEmpty) {
      // Query cleared — restore display from active filter (or all heroes).
      await _shqlBindings.eval('UPDATE_DISPLAYED_HEROES()');
      _rebuildHeroCards();
      _onStateChanged();
      return;
    }
    _setAndNotify('_filtering', true);
    try {
      final lambda = await _filterCompiler.compileQuery(query);

      if (lambda == null) {
        // No compilable filter — show all heroes.
        await _shqlBindings.eval('UPDATE_DISPLAYED_HEROES()');
        _rebuildHeroCards();
        _onStateChanged();
        return;
      }

      // Let SHQL™ iterate _heroes and apply the predicate via _EVAL_PREDICATE.
      await _shqlBindings.eval(
        'FILTER_DISPLAYED(__pred, __predText)',
        boundValues: {'__pred': lambda, '__predText': query},
      );
      _rebuildHeroCards();
      _onStateChanged();
    } finally {
      _setAndNotify('_filtering', false);
    }
  }

  // ---------------------------------------------------------------------------
  // Hero service
  // ---------------------------------------------------------------------------

  Future<HeroService?> getHeroService() async {
    var apiKey = _shqlBindings.getVariable('_api_key');
    if (apiKey == null || apiKey.toString().isEmpty || apiKey == 'null') {
      final entered = await _showPromptDialog('Enter your API key:');
      if (entered.isEmpty) return null;
      await _shqlBindings.eval("SET_API_KEY('$entered')");
      apiKey = entered;
    }

    const defaultApiHost = 'www.superheroapi.com';
    var apiHost = _shqlBindings.getVariable('_api_host');
    if (apiHost == null || apiHost.toString().isEmpty || apiHost == 'null') {
      final entered = await _showPromptDialog(
        'Enter API host or press enter to accept default ("$defaultApiHost"):',
        defaultApiHost,
      );
      apiHost = entered.isNotEmpty ? entered : defaultApiHost;
      await _shqlBindings.eval("SET_API_HOST('$apiHost')");
    }

    return HeroService(Env.create(apiKey: apiKey.toString(), apiHost: apiHost.toString()));
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

  void _setAndNotify(String name, dynamic value) {
    _shqlBindings.setVariable(name, value);
    _shqlBindings.notifyListeners(name);
  }

  /// Updates `_displayed_heroes` via SHQL™, then rebuilds `_hero_cards` from
  /// the per-ID cache. No SHQL™ eval for card generation — O(displayed) map lookups.
  Future<void> _updateDisplayedHeroes() async {
    await _shqlBindings.eval('UPDATE_DISPLAYED_HEROES()');
    _rebuildHeroCards();
  }

  /// Populates the per-ID card cache for all saved heroes and rebuilds
  /// `_hero_cards`. Call after initialize() + rebuildAllFilters() at startup.
  ///
  /// [onProgress] is called before each hero is cached with (current, total, heroName).
  Future<void> populateHeroCardCache({
    void Function(int current, int total, String heroName)? onProgress,
  }) async {
    _heroCardCache.clear();
    final entries = _heroDataManager.heroObjectsById.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final heroName = _heroDataManager.getById(entry.key)?.name ?? '';
      onProgress?.call(i + 1, entries.length, heroName);
      await _cacheHeroCard(entry.key, entry.value);
    }
    _rebuildHeroCards();
  }

  /// Calls SHQL™ GENERATE_SINGLE_HERO_CARD for one hero and stores the result.
  Future<void> _cacheHeroCard(String heroId, Object heroObj) async {
    final card = await _shqlBindings.eval(
      'GENERATE_SINGLE_HERO_CARD(__hero)',
      boundValues: {'__hero': heroObj},
    );
    if (card != null) {
      _heroCardCache[heroId] = card;
    }
  }

  void _removeHeroFromCache(String heroId) => _heroCardCache.remove(heroId);

  /// Called when `_displayed_heroes` changes (from any source — Dart or SHQL™).
  void onDisplayedHeroesChanged() => _rebuildHeroCards();

  /// Rebuilds `_hero_cards` from `_heroCardCache` + `_displayed_heroes`.
  /// Synchronous — no SHQL™ eval. Handles three states:
  ///   • Cache empty → [] (YAML shows the "no heroes saved" empty state)
  ///   • Cache non-empty but displayed empty → single "no match" widget
  ///   • Otherwise → cards for each displayed hero, in display order
  void _rebuildHeroCards() {
    if (_heroCardCache.isEmpty) {
      _setAndNotify('_hero_cards', <dynamic>[]);
      return;
    }

    final displayed = _shqlBindings.getVariable('_displayed_heroes');
    if (displayed is! List || displayed.isEmpty) {
      final query = _shqlBindings.getVariable('_current_query')?.toString() ?? '';
      final msg = query.trim().isNotEmpty
          ? 'No heroes match "$query"'
          : 'No heroes match this filter';
      _setAndNotify('_hero_cards', [
        {'type': 'Center', 'child': {'type': 'Text', 'props': {'data': msg, 'style': {'fontSize': 16, 'color': '0xFF757575'}}}}
      ]);
      return;
    }

    final cards = <dynamic>[];
    for (final heroObj in displayed) {
      if (_shqlBindings.isShqlObject(heroObj)) {
        final id = _shqlBindings.objectToMap(heroObj)['id'] as String?;
        if (id != null) {
          final card = _heroCardCache[id];
          if (card != null) cards.add(card);
        }
      }
    }
    _setAndNotify('_hero_cards', cards);
  }
}
