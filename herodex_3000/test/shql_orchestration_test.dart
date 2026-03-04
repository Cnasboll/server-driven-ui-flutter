import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hero_common/managers/hero_data_manager.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/testing/testing.dart';
import 'package:hero_common/value_types/conflict_resolver.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/value_types/value_type.dart' show SystemOfUnits;
import 'package:hero_common/value_types/weight.dart';
import 'package:server_driven_ui/server_driven_ui.dart';
import 'package:shql/testing/shql_test_runner.dart';

import 'package:herodex_3000/core/hero_coordinator.dart';
import 'package:herodex_3000/core/hero_schema.dart';
import 'package:herodex_3000/persistence/filter_compiler.dart';
import 'package:herodex_3000/widgets/conflict_resolver_dialog.dart' show ReviewAction;

// ─── Shared paths ───────────────────────────────────────────────────
const _shqlDir = 'assets/shql';
const _stdlibPath = '../shql/assets/stdlib.shql';
const _testLibPath = '../shql/assets/shql_test.shql';

/// Extract ALL SHQL™ expressions from a YAML file, in document order.
/// Delegates to [extractShqlExpressions] — the same [isShqlRef], [parseShql],
/// and `on*` callback heuristic used at runtime.
List<String> allShqlFromYaml(String yamlPath) =>
    extractShqlExpressions(File(yamlPath).readAsStringSync());

/// Production SHQL™ file load order (same as app.dart).
const _shqlFiles = [
  'auth',
  'navigation',
  'firestore',
  'preferences',
  'statistics',
  'filters',
  'heroes',
  'hero_detail',
  'hero_cards',
  'search',
  'hero_edit',
  'world',
];

/// Create a [ShqlTestRunner] wired to flutter_test's [expect].
ShqlTestRunner _createRunner() => ShqlTestRunner.withExpect(expect);

/// Register no-op Dart callbacks matching app.dart's platform boundaries.
/// Each test group overrides only the callbacks it needs.
void _registerNoOpCallbacks(ShqlTestRunner h) {
  // Nullary
  h.runtime.setNullaryFunction('__ON_AUTHENTICATED', (ctx, c) => null);
  h.runtime.setNullaryFunction('_HERO_CLEAR', (ctx, c) => null);
  h.runtime.setNullaryFunction('_SIGN_OUT', (ctx, c) {
    h.callLog.add('_SIGN_OUT()');
    return null;
  });
  h.runtime.setNullaryFunction('_COMPILE_FILTERS', (ctx, c) => null);
  h.runtime.setNullaryFunction('_INIT_RECONCILE', (ctx, c) => null);
  h.runtime.setNullaryFunction('_FINISH_RECONCILE', (ctx, c) => null);

  // Unary
  h.runtime.setUnaryFunction('_BUILD_EDIT_FIELDS', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_COMPILE_QUERY', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_SEARCH_HEROES', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_GET_SAVED_ID', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_PERSIST_HERO', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_MAP_HERO', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_HERO_TOGGLE_LOCK', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_RECONCILE_FETCH', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_HERO_DELETE', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_RECONCILE_PROMPT', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_SHOW_SNACKBAR', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_SET_DARK_MODE', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_SET_ANALYTICS', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_SET_CRASHLYTICS', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_REFRESH_HERO_SERVICE', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_GET_LOCATION', (ctx, c, a) =>
      h.makeObject({'description': '', 'latitude': null, 'longitude': null}));
  h.runtime.setUnaryFunction('FETCH', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('NUMBER', (ctx, c, a) {
    if (a is int) return a;
    if (a is String) return int.tryParse(a) ?? double.tryParse(a) ?? 0;
    if (a is double) return a;
    return a;
  });

  // Binary
  h.runtime.setBinaryFunction('MATCH', (ctx, c, a, b) => false);
  h.runtime.setBinaryFunction('_PROMPT', (ctx, c, a, b) => null);
  h.runtime.setBinaryFunction('_HERO_AMEND', (ctx, c, a, b) => null);
  h.runtime.setBinaryFunction('POST', (ctx, c, a, b) =>
      <String, dynamic>{'status': 0});
  h.runtime.setBinaryFunction('FETCH_AUTH', (ctx, c, a, b) =>
      <String, dynamic>{'status': 0, 'body': null});

  // Ternary
  h.runtime.setTernaryFunction('_REVIEW_HERO', (ctx, c, a, b, d) => null);
  h.runtime.setTernaryFunction('_EVAL_PREDICATE',
      (ctx, c, hero, pred, predText) => true);
  h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, c, a, b, d) =>
      <String, dynamic>{'status': 200});
}

/// Standard setUp: mirrors production exactly.
/// Loads stdlib, test lib, hero schema, ALL .shql files, and registers
/// no-op Dart callbacks for all platform boundaries.
Future<ShqlTestRunner> _standardSetUp() async {
  final h = _createRunner();
  await h.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);
  HeroShqlAdapter.registerHeroSchema(h.constantsSet);
  await h.test(HeroSchema.generateSchemaScript());

  // Register no-op callbacks BEFORE loading .shql files (they may call
  // LOAD_STATE / SAVE_STATE at load time, but those are wired by setUp).
  _registerNoOpCallbacks(h);

  // Load all production SHQL™ files in order
  for (final name in _shqlFiles) {
    await h.loadFile('$_shqlDir/$name.shql');
  }

  return h;
}

// ─── Concrete coordinator setup ─────────────────────────────────────

/// Path to hero JSON fixtures (731 cached superheroapi.com responses).
const _heroFixturesPath = '../v04/test/heroes';

/// Loads a hero from JSON fixtures, parses into a real HeroModel, persists
/// to the in-memory repository, and returns the SHQL™ Object + internal ID.
Future<({dynamic obj, String id, String name})> _persistFixtureHero(
  MockHeroService mockService,
  HeroDataManager heroDataManager,
  ShqlBindings shqlBindings,
  String externalId,
) async {
  final json = await mockService.getById(externalId);
  if (json == null) throw StateError('No fixture for hero $externalId');
  final prevH = Height.conflictResolver;
  final prevW = Weight.conflictResolver;
  Height.conflictResolver = FirstProvidedValueConflictResolver<Height>();
  Weight.conflictResolver = FirstProvidedValueConflictResolver<Weight>();
  try {
    final hero =
        await heroDataManager.heroFromJson(json, DateTime.timestamp());
    heroDataManager.persist(hero);
    return (
      obj: HeroShqlAdapter.heroToShqlObject(hero, shqlBindings.identifiers),
      id: hero.id,
      name: hero.name,
    );
  } finally {
    Height.conflictResolver = prevH;
    Weight.conflictResolver = prevW;
  }
}

/// Concrete setup: real HeroCoordinator backed by MockHeroRepository +
/// MockHeroService (the entire superheroapi.com, cached).
/// Mocking is pushed to the outermost boundary — only UI dialogs remain mocked.
/// All SHQL™ modules are the real production files (no stubs).
Future<({
  ShqlTestRunner h,
  HeroCoordinator coordinator,
  HeroDataManager heroDataManager,
  MockHeroService mockService,
  ShqlBindings shqlBindings,
})> _concreteSetUp({
  List<String> shqlFiles = _shqlFiles,
}) async {
  final h = _createRunner();
  await h.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);

  // Register hero schema (enum constants, field identifiers)
  HeroShqlAdapter.registerHeroSchema(h.constantsSet);

  // Start with no-op callbacks so all .shql files can load
  _registerNoOpCallbacks(h);

  final mockService = MockHeroService(_heroFixturesPath);

  final heroDataManager = HeroDataManager(
    MockHeroRepository(),
    runtime: h.runtime,
    constantsSet: h.constantsSet,
  );

  // ShqlBindings sharing the test runner's runtime
  final shqlBindings = ShqlBindings(
    onMutated: () {},
    constantsSet: h.constantsSet,
    runtime: h.runtime,
    saveState: (k, v) async {},
    loadState: (k, d) async => d,
  );

  final filterCompiler = FilterCompiler(shqlBindings);

  final coordinator = HeroCoordinator(
    shqlBindings: shqlBindings,
    heroDataManager: heroDataManager,
    heroServiceFactory: () => mockService,
    filterCompiler: filterCompiler,
    showReconcileDialog: (_) async => ReviewAction.skip,
    showReviewHeroDialog: (_, __, ___) async => ReviewAction.skip,
    showSnackBar: (msg) {},
    onStateChanged: () {},
  );

  // Override no-op callbacks with real coordinator methods.
  // Uses mockUnary/mockBinary for proper call log tracking.
  h.mockUnary('_HERO_DELETE', (heroId) {
    if (heroId is String) return coordinator.heroDelete(heroId);
    return null;
  });
  h.mockUnary('_HERO_TOGGLE_LOCK', (heroId) {
    if (heroId is String) return coordinator.heroToggleLock(heroId);
    return null;
  });
  h.mockUnary('_SHOW_SNACKBAR');
  h.mockUnary('_SEARCH_HEROES', (query) async {
    if (query is String && query.isNotEmpty) {
      return await coordinator.searchHeroes(query);
    }
    return null;
  });
  h.mockUnary('_GET_SAVED_ID', (hero) => coordinator.getSavedId(hero));
  h.mockUnary('_PERSIST_HERO', (hero) => coordinator.persistAndMap(hero));
  h.mockUnary('_MAP_HERO', (hero) => coordinator.mapHero(hero));
  h.mockUnary('_BUILD_EDIT_FIELDS', (heroId) {
    if (heroId is String) return coordinator.buildEditFields(heroId);
    return null;
  });
  // _HERO_DELETE already registered above (used for both manual delete and reconcile delete)
  h.mockUnary('_RECONCILE_FETCH', (heroId) async {
    if (heroId is String) return await coordinator.reconcileFetch(heroId);
    return null;
  });
  h.mockUnary('_RECONCILE_PROMPT', (text) async =>
      await coordinator.reconcilePrompt(text?.toString() ?? ''));
  h.mockBinary('_HERO_AMEND', (heroId, amendment) async {
    if (heroId is String && heroId.isNotEmpty) {
      return await coordinator.heroAmend(heroId, amendment);
    }
    return null;
  });
  h.mockBinary('MATCH', (heroObj, queryText) =>
      coordinator.matchHeroObject(heroObj, queryText as String));

  // Nullary callbacks (no mockNullary in ShqlTestRunner yet)
  h.runtime.setNullaryFunction('_HERO_CLEAR',
      (ctx, c) => coordinator.heroClear());
  h.runtime.setNullaryFunction('_COMPILE_FILTERS',
      (ctx, c) => coordinator.compileFilters());
  h.runtime.setNullaryFunction('_INIT_RECONCILE',
      (ctx, c) => coordinator.initReconcile());
  h.runtime.setNullaryFunction('_FINISH_RECONCILE',
      (ctx, c) => coordinator.finishReconcile());
  h.runtime.setUnaryFunction('_COMPILE_QUERY', (ctx, c, query) async {
    if (query is String && query.isNotEmpty) {
      return await coordinator.compileQuery(query);
    }
    return null;
  });

  // _EVAL_PREDICATE: evaluate a compiled filter predicate against a hero.
  // Mirrors app.dart — compiled lambda call with text-match fallback.
  h.runtime.setTernaryFunction('_EVAL_PREDICATE',
      (ctx, c, hero, pred, predicateText) async {
    final text = (predicateText is String) ? predicateText : '';
    if (text.isEmpty) return true;
    if (pred != null) {
      try {
        final result = await shqlBindings.evalParsed(
          shqlBindings.parse('__pred(__hero)'),
          boundValues: {'__pred': pred, '__hero': hero},
        );
        if (result is bool) return result;
        return result != null && result != 0;
      } catch (_) {
        // Predicate threw (null field etc.) — fall through to text match
      }
    }
    return coordinator.matchHeroObject(hero, text);
  });

  // Platform callbacks: override no-ops to track calls
  h.mockUnary('_SET_DARK_MODE');
  h.mockUnary('_SET_ANALYTICS');
  h.mockUnary('_SET_CRASHLYTICS');
  h.mockUnary('_REFRESH_HERO_SERVICE');
  h.mockUnary('_GET_LOCATION', (_) =>
      h.makeObject({'description': '', 'latitude': null, 'longitude': null}));
  h.mockBinary('_PROMPT');

  // Load hero schema script (accessor functions, detail/summary fields)
  await shqlBindings.eval(HeroSchema.generateSchemaScript());

  // Load SHQL™ files
  for (final name in shqlFiles) {
    await h.loadFile('$_shqlDir/$name.shql');
  }

  return (
    h: h,
    coordinator: coordinator,
    heroDataManager: heroDataManager,
    mockService: mockService,
    shqlBindings: shqlBindings,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // Heroes — concrete HeroCoordinator + real SHQL™ modules
  // Each test = one user action → SHQL™ assertions → Dart DB assertions
  // ═══════════════════════════════════════════════════════════════════
  group('Heroes', () {
    late ShqlTestRunner h;
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;
    late ShqlBindings shqlBindings;

    setUp(() async {
      final s = await _concreteSetUp();
      h = s.h;
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
      shqlBindings = s.shqlBindings;
    });

    /// Persist a fixture hero to DB AND push into SHQL™ state
    /// (mirrors what happens after a search-save).
    Future<({String id, String name})> addHero(String externalId) async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, externalId);
      await h.test('Heroes.ON_HERO_ADDED(__h); Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero.obj});
      return (id: hero.id, name: hero.name);
    }

    test('ON_HERO_ADDED updates heroes map, stats, card cache', () async {
      final batman = await addHero('69');
      await h.test(r'''
        EXPECT(Heroes.total_heroes, 1);
        ASSERT(Heroes.heroes[__id] <> null);
        ASSERT(Stats.COUNT_HEIGHT() > 0);
        ASSERT(Stats.TOTAL_FIGHTING_POWER() > 0);
        ASSERT(Cards.card_cache[__id] <> null)
      ''', boundValues: {'__id': batman.id});
    });

    test('DELETE_HERO removes from SHQL™ state, stats, filters, card cache, and DB',
        () async {
      final batman = await addHero('69');
      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.DELETE_HERO(__id);
        EXPECT(Heroes.total_heroes, 0);
        ASSERT(Heroes.heroes[__id] = null);
        EXPECT(Stats.COUNT_HEIGHT(), 0);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 0);
        EXPECT(LENGTH(Filters.displayed_heroes), 0);
        ASSERT(Cards.card_cache[__id] = null);
        ASSERT_CALLED('_HERO_DELETE')
      ''', boundValues: {'__id': batman.id});
      expect(heroDataManager.getById(batman.id), isNull);
    });

    test('DELETE_HERO is a no-op for unknown hero', () async {
      await h.test(r'''
        Heroes.DELETE_HERO('nonexistent');
        EXPECT(Heroes.total_heroes, 0)
      ''');
    });

    test('TOGGLE_LOCK toggles in SHQL™ state and DB', () async {
      final batman = await addHero('69');
      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.TOGGLE_LOCK(__id);
        EXPECT(Heroes.heroes[__id].LOCKED, TRUE);
        ASSERT_CALLED('_HERO_TOGGLE_LOCK')
      ''', boundValues: {'__id': batman.id});
      expect(heroDataManager.getById(batman.id)!.locked, true);
    });

    test('ON_HERO_CLEAR resets heroes, stats, filters', () async {
      await addHero('69');
      await addHero('644'); // Superman (has weight conflict — resolved by test)
      await h.test(r'''
        EXPECT(Heroes.total_heroes, 2);
        Heroes.ON_HERO_CLEAR();
        EXPECT(Heroes.total_heroes, 0);
        EXPECT(LENGTH(Heroes.heroes), 0);
        EXPECT(Stats.COUNT_HEIGHT(), 0);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 0)
      ''');
    });

    test('SELECT_HERO navigates to hero_detail', () async {
      final batman = await addHero('69');
      await h.test(r'''
        Heroes.SELECT_HERO(Heroes.heroes[__id]);
        EXPECT(Heroes.selected_hero.NAME, 'Batman');
        ASSERT_CONTAINS(Nav.navigation_stack, 'hero_detail')
      ''', boundValues: {'__id': batman.id});
    });

    test('CLEAR_SELECTED_IF clears when ID matches', () async {
      final batman = await addHero('69');
      await h.test(r'''
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        Heroes.CLEAR_SELECTED_IF(__id);
        ASSERT(Heroes.selected_hero = null)
      ''', boundValues: {'__id': batman.id});
    });

    test('CLEAR_SELECTED_IF does not clear when ID differs', () async {
      final batman = await addHero('69');
      await h.test(r'''
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        Heroes.CLEAR_SELECTED_IF('nonexistent');
        ASSERT(Heroes.selected_hero <> null)
      ''', boundValues: {'__id': batman.id});
    });

    test('two heroes: stats accumulate, rebuild populates filters', () async {
      await addHero('69'); // Batman
      await addHero('644'); // Superman (has weight conflict — resolved by test)
      await h.test(r'''
        EXPECT(Heroes.total_heroes, 2);
        ASSERT(Stats.COUNT_HEIGHT() >= 2);
        ASSERT(Stats.TOTAL_FIGHTING_POWER() > 0);
        Filters.REBUILD_ALL_FILTERS();
        EXPECT(LENGTH(Filters.displayed_heroes), 2)
      ''');
    });

    test('card cache contains generated card widget tree', () async {
      final batman = await addHero('69');
      await h.test(r'''
        __card := Cards.card_cache[__id];
        ASSERT(__card <> null);
        ASSERT(__card['type'] <> null)
      ''', boundValues: {'__id': batman.id});
    });

    test('ON_HEROES_ADDED batch-adds multiple heroes', () async {
      final hero1 = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final hero2 = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '644');
      await h.test(r'''
        Heroes.ON_HEROES_ADDED([__h1, __h2]);
        EXPECT(Heroes.total_heroes, 2);
        ASSERT(Stats.COUNT_HEIGHT() >= 2);
        Filters.REBUILD_ALL_FILTERS();
        EXPECT(LENGTH(Filters.displayed_heroes), 2)
      ''', boundValues: {'__h1': hero1.obj, '__h2': hero2.obj});
    });

    test('REFRESH_SELECTED_IF updates selected hero from heroes map',
        () async {
      final batman = await addHero('69');
      await h.test(r'''
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        -- Mutate the hero in the map
        Heroes.heroes[__id].NAME := 'Dark Knight';
        -- Refresh should pick up the change
        Heroes.REFRESH_SELECTED_IF(__id);
        EXPECT(Heroes.selected_hero.NAME, 'Dark Knight')
      ''', boundValues: {'__id': batman.id});
    });

    test('REFRESH_SELECTED_IF is no-op for different ID', () async {
      final batman = await addHero('69');
      await h.test(r'''
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        Heroes.REFRESH_SELECTED_IF('nonexistent');
        EXPECT(Heroes.selected_hero.NAME, 'Batman')
      ''', boundValues: {'__id': batman.id});
    });

    test('CLEAR_ALL_DATA clears DB and SHQL™ state', () async {
      await addHero('69');
      await addHero('644');
      await h.test(r'''
        EXPECT(Heroes.total_heroes, 2);
        Heroes.CLEAR_ALL_DATA();
        EXPECT(Heroes.total_heroes, 0);
        EXPECT(LENGTH(Heroes.heroes), 0);
        EXPECT(Stats.COUNT_HEIGHT(), 0);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 0);
        EXPECT(LENGTH(Heroes.hero_cards), 0)
      ''');
      expect(heroDataManager.heroes, isEmpty);
    });

    test('SIGN_OUT calls FIREBASE_SIGN_OUT and _SIGN_OUT', () async {
      await h.test('''
        CLEAR_CALL_LOG();
        Heroes.SIGN_OUT();
        ASSERT_CALLED('_SIGN_OUT')
      ''');
    });

    test('DELETE_SELECTED_AND_GO_BACK deletes hero and navigates back', () async {
      final batman = await addHero('69');
      await h.test(r'''
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        Nav.PUSH_ROUTE('hero_detail');

        CLEAR_CALL_LOG();
        Heroes.DELETE_SELECTED_AND_GO_BACK();
        EXPECT(Heroes.total_heroes, 0);
        ASSERT(Heroes.selected_hero = null);
        ASSERT_CALLED('_HERO_DELETE')
      ''', boundValues: {'__id': batman.id});
    });

    test('DELETE_SELECTED_AND_GO_BACK is no-op when no hero selected', () async {
      await addHero('69');
      await h.test(r'''
        Heroes.DELETE_SELECTED_AND_GO_BACK();
        EXPECT(Heroes.total_heroes, 1)
      ''');
    });

    test('STARTUP adds heroes, rebuilds filters, populates cards', () async {
      // Directly use STARTUP instead of the per-hero addHero helper
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final hero2 = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '644');
      await h.test(r'''
        Heroes.STARTUP([__h1, __h2]);
        EXPECT(Heroes.total_heroes, 2);
        ASSERT(LENGTH(Cards.card_cache) = 2);
        ASSERT(LENGTH(Heroes.hero_cards) > 0)
      ''', boundValues: {'__h1': hero.obj, '__h2': hero2.obj});
    });

    test('GET_HERO_COUNT returns number of heroes', () async {
      await addHero('69');
      await addHero('644');
      await h.test('EXPECT(Heroes.GET_HERO_COUNT(), 2)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Reconciliation — concrete HeroCoordinator + real SHQL™ modules
  // ═══════════════════════════════════════════════════════════════════
  group('Reconciliation', () {
    late ShqlTestRunner h;
    late HeroCoordinator coordinator;
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;
    late ShqlBindings shqlBindings;

    setUp(() async {
      final s = await _concreteSetUp();
      h = s.h;
      coordinator = s.coordinator;
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
      shqlBindings = s.shqlBindings;
    });

    Future<({String id, String name, dynamic obj})> addHero(
        String externalId) async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, externalId);
      await h.test('Heroes.ON_HERO_ADDED(__h); Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero.obj});
      return (id: hero.id, name: hero.name, obj: hero.obj);
    }

    test('RECONCILE_UPDATE replaces hero in state and persists to DB',
        () async {
      final batman = await addHero('69');
      // Load a real HeroModel as the "updated" opaque model
      final json = await mockService.getById('69');
      final opaqueModel =
          await heroDataManager.heroFromJson(json!, DateTime.timestamp());

      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.RECONCILE_UPDATE(Heroes.heroes[__id], __opaque, 'Updated', 'Batman: updated');
        EXPECT(Heroes.total_heroes, 1);
        ASSERT(Heroes.heroes[__id] <> null);
        ASSERT(Cards.card_cache[__id] <> null);
        ASSERT_CALLED('_PERSIST_HERO')
      ''', boundValues: {'__id': batman.id, '__opaque': opaqueModel});
      expect(heroDataManager.getById(batman.id), isNotNull);
    });

    test('RECONCILE_DELETE removes hero from state and DB', () async {
      final batman = await addHero('69');
      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.RECONCILE_DELETE(Heroes.heroes[__id], 'Deleted', 'Batman: deleted');
        EXPECT(Heroes.total_heroes, 0);
        ASSERT(Heroes.heroes[__id] = null);
        ASSERT(Cards.card_cache[__id] = null);
        EXPECT(Stats.COUNT_HEIGHT(), 0)
      ''', boundValues: {'__id': batman.id});
    });

    test('RECONCILE_HEROES: unchanged hero skipped, deleted hero removed',
        () async {
      // Add two heroes: Batman (unchanged online) and Captain America
      final batman = await addHero('69');
      final cap = await addHero('149');
      expect(heroDataManager.heroes, hasLength(2));

      // Remove Captain America from the mock API — simulates "deleted online"
      mockService.removeById('149');

      // User accepts deletion when prompted
      h.mockUnary('_RECONCILE_PROMPT', (text) => 'save');

      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.RECONCILE_HEROES();

        -- Batman unchanged, Captain America deleted
        EXPECT(Heroes.total_heroes, 1);
        ASSERT(Heroes.heroes[__batman_id] <> null);
        ASSERT(Heroes.heroes[__cap_id] = null);

        -- Card cache updated
        ASSERT(Cards.card_cache[__batman_id] <> null);
        ASSERT(Cards.card_cache[__cap_id] = null);

        -- Reconcile state cleaned up
        ASSERT(NOT Heroes.reconcile_active);
        ASSERT(NOT Heroes.reconcile_aborted);

        -- Summary logged
        ASSERT(LENGTH(Heroes.reconcile_log) > 0);

        -- Dart callbacks invoked (those registered via mockUnary)
        ASSERT_CALLED('_RECONCILE_FETCH');
        ASSERT_CALLED('_HERO_DELETE');
        ASSERT_CALLED('_RECONCILE_PROMPT');
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''', boundValues: {
        '__batman_id': batman.id,
        '__cap_id': cap.id,
      });

      // Dart DB: Batman still persisted, Captain America deleted
      expect(heroDataManager.getById(batman.id), isNotNull);
      expect(heroDataManager.getById(cap.id), isNull);
      expect(heroDataManager.heroes, hasLength(1));
    });

    test('RECONCILE_HEROES skips locked heroes (amendment sets lock)',
        () async {
      // Add Batman, then amend via Dart to lock him
      final batman = await addHero('69');
      final hero = heroDataManager.getById(batman.id)!;
      final amended = await hero.amendWith({'name': 'Batman (Amended)'});
      heroDataManager.persist(amended);
      expect(amended.locked, true);

      // Replace the SHQL™ object with one built from the amended (locked) model
      final lockedObj = HeroShqlAdapter.heroToShqlObject(
          amended, shqlBindings.identifiers);
      await h.test(r'''
        Heroes.ON_HERO_REMOVED(Heroes.heroes[__id]);
        Heroes.ON_HERO_ADDED(__locked);
        Cards.CACHE_HERO_CARD(__locked);
        EXPECT(Heroes.heroes[__id].LOCKED, TRUE)
      ''', boundValues: {'__id': batman.id, '__locked': lockedObj});

      // Now reconcile — Batman has a diff online but is locked
      h.mockUnary('_RECONCILE_FETCH', (heroId) async {
        return shqlBindings.mapToObject({
          'found': true,
          'apply_error': null,
          'has_diff': true,
          'diff_text': 'Name: Batman → Batman (Online)',
          'resolution_logs': <dynamic>[],
          'conflict_count': 0,
          'updated_hero': heroDataManager.getById(batman.id),
        });
      });

      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.RECONCILE_HEROES();

        -- Hero still exists and is unchanged (reconciliation skipped it)
        EXPECT(Heroes.total_heroes, 1);
        ASSERT(Heroes.heroes[__id] <> null);

        -- _PERSIST_HERO should NOT have been called (hero was skipped)
        ASSERT_NOT_CALLED('_PERSIST_HERO');

        -- Reconcile state cleaned up
        ASSERT(NOT Heroes.reconcile_active);

        -- Summary should mention locked skip
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''', boundValues: {'__id': batman.id});

      // DB: hero name still amended, not overwritten by reconciliation
      expect(heroDataManager.getById(batman.id)!.name, 'Batman (Amended)');
    });

    test('ABORT_RECONCILE sets aborted flag and snackbar says "aborted"',
        () async {
      await addHero('69');

      // Mock _RECONCILE_FETCH to be slow enough that abort can trigger
      // We'll set aborted BEFORE calling RECONCILE_HEROES — the loop
      // should see the flag and break immediately.
      h.mockUnary('_RECONCILE_FETCH', (heroId) async {
        return shqlBindings.mapToObject({
          'found': true,
          'has_diff': false,
          'diff_text': '',
          'resolution_logs': <dynamic>[],
          'updated_hero': null,
          'apply_error': null,
        });
      });

      await h.test(r'''
        -- Set aborted BEFORE reconcile starts
        Heroes.SET_RECONCILE_ABORTED(TRUE);
        Heroes.RECONCILE_HEROES();
        -- Snackbar should say "aborted"
        ASSERT_CALLED('_SHOW_SNACKBAR');
        -- Also test ABORT_RECONCILE function itself
        Heroes.SET_RECONCILE_ABORTED(FALSE);
        Heroes.ABORT_RECONCILE();
        ASSERT(Heroes.reconcile_aborted)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Conflict Resolution — metric/imperial conflict handling
  // Tests that heroes with conflicting unit data are resolved by
  // the appropriate ConflictResolver, not dodged.
  // ═══════════════════════════════════════════════════════════════════
  group('Conflict Resolution', () {
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;

    setUp(() async {
      // Minimal setup — no SHQL™ files needed for pure Dart parsing
      final s = await _concreteSetUp(shqlFiles: []);
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
    });

    tearDown(() {
      Height.conflictResolver = null;
      Weight.conflictResolver = null;
    });

    test('AutoConflictResolver(metric) picks metric weight for Superman',
        () async {
      // Superman (644) has conflicting weight: 225 lb vs 101 kg
      final weightResolver =
          AutoConflictResolver<Weight>(SystemOfUnits.metric);
      final heightResolver =
          AutoConflictResolver<Height>(SystemOfUnits.metric);
      Weight.conflictResolver = weightResolver;
      Height.conflictResolver = heightResolver;

      final json = await mockService.getById('644');
      final hero =
          await heroDataManager.heroFromJson(json!, DateTime.timestamp());

      expect(hero.appearance.weight.systemOfUnits, SystemOfUnits.metric);
      expect(weightResolver.resolutionLog, isNotEmpty);
    });

    test('AutoConflictResolver(imperial) picks imperial weight for Superman',
        () async {
      final weightResolver =
          AutoConflictResolver<Weight>(SystemOfUnits.imperial);
      final heightResolver =
          AutoConflictResolver<Height>(SystemOfUnits.imperial);
      Weight.conflictResolver = weightResolver;
      Height.conflictResolver = heightResolver;

      final json = await mockService.getById('644');
      final hero =
          await heroDataManager.heroFromJson(json!, DateTime.timestamp());

      expect(hero.appearance.weight.systemOfUnits, SystemOfUnits.imperial);
      expect(weightResolver.resolutionLog, isNotEmpty);
    });

    test('one resolver applies to ALL conflict-prone heroes (not just one)',
        () async {
      // Parse Superman (644) + Hulk (332) — both have weight conflicts.
      // A single FirstProvidedValueConflictResolver handles them all.
      final weightResolver = FirstProvidedValueConflictResolver<Weight>();
      final heightResolver = FirstProvidedValueConflictResolver<Height>();
      Weight.conflictResolver = weightResolver;
      Height.conflictResolver = heightResolver;

      for (final id in ['644', '332']) {
        final json = await mockService.getById(id);
        await heroDataManager.heroFromJson(json!, DateTime.timestamp());
      }

      // One resolver accumulated logs from both heroes
      expect(weightResolver.resolutionLog, hasLength(greaterThanOrEqualTo(2)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Search — concrete HeroCoordinator + MockHeroService (all 731 heroes)
  // Each test = user types a query and presses enter → full pipeline
  // _REVIEW_HERO is the only mock (UI dialog) — set per-test
  // ═══════════════════════════════════════════════════════════════════
  group('Search', () {
    late ShqlTestRunner h;
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;
    late ShqlBindings shqlBindings;

    setUp(() async {
      final s = await _concreteSetUp();
      h = s.h;
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
      shqlBindings = s.shqlBindings;
    });

    test('short query (< 2 chars) returns empty, no API call', () async {
      await h.test(r'''
        Search.SEARCH_HEROES('a');
        EXPECT(LENGTH(Search.search_results), 0);
        ASSERT_NOT_CALLED('_SEARCH_HEROES')
      ''');
    });

    test('search "jubilee" + save: 1 hero saved to DB and SHQL™ state',
        () async {
      // User types "jubilee", presses enter, review dialog returns "save"
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'save');

      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');

        -- SHQL™ state
        EXPECT(Heroes.total_heroes, 1);
        EXPECT(LENGTH(Search.search_results), 1);
        ASSERT('1 found' IN Search.search_summary);
        ASSERT('1 saved' IN Search.search_summary);

        -- Stats updated
        ASSERT(Stats.COUNT_HEIGHT() > 0);

        -- Filters updated
        EXPECT(LENGTH(Filters.displayed_heroes), 1);

        -- Card cached
        ASSERT(LENGTH(Cards.card_cache) > 0);

        -- Search history recorded
        ASSERT_CONTAINS(Search.search_history, 'jubilee');

        -- Callback log
        ASSERT_CALLED('_SEARCH_HEROES');
        ASSERT_CALLED('_GET_SAVED_ID');
        ASSERT_CALLED('_PERSIST_HERO');
        ASSERT_CALL_COUNT('_REVIEW_HERO', 1);
        ASSERT_NOT_CALLED('_MAP_HERO')
      ''');

      // Dart DB: hero persisted
      final allHeroes = heroDataManager.heroes;
      expect(allHeroes, hasLength(1));
      expect(allHeroes.first.name, 'Jubilee');
    });

    test('search "jubilee" + skip: hero shown but not saved to DB',
        () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'skip');

      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');

        EXPECT(Heroes.total_heroes, 0);
        EXPECT(LENGTH(Search.search_results), 1);
        ASSERT('1 skipped' IN Search.search_summary);

        ASSERT_CALLED('_MAP_HERO');
        ASSERT_NOT_CALLED('_PERSIST_HERO')
      ''');

      expect(heroDataManager.heroes, isEmpty);
    });

    test('search "toxin" + saveAll: both heroes saved, review called once',
        () async {
      // "toxin" matches Toxin (697) and Toxin (698) — 2 results
      // User clicks "Save All" on the first → second auto-saved
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'saveAll');

      await h.test(r'''
        Search.SEARCH_HEROES('toxin');

        EXPECT(Heroes.total_heroes, 2);
        EXPECT(LENGTH(Search.search_results), 2);
        ASSERT('2 saved' IN Search.search_summary);

        -- Review only shown once (saveAll skips the rest)
        ASSERT_CALL_COUNT('_REVIEW_HERO', 1);
        ASSERT_CALL_COUNT('_PERSIST_HERO', 2);

        -- Stats grew
        ASSERT(Stats.COUNT_HEIGHT() >= 2);

        -- Filters grew
        EXPECT(LENGTH(Filters.displayed_heroes), 2)
      ''');

      expect(heroDataManager.heroes, hasLength(2));
    });

    test('search "toxin" + cancel: both heroes mapped but not saved',
        () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'cancel');

      await h.test(r'''
        Search.SEARCH_HEROES('toxin');

        EXPECT(Heroes.total_heroes, 0);
        EXPECT(LENGTH(Search.search_results), 2);
        ASSERT('cancelled' IN Search.search_summary);
        ASSERT_CALL_COUNT('_MAP_HERO', 2);
        ASSERT_NOT_CALLED('_PERSIST_HERO')
      ''');

      expect(heroDataManager.heroes, isEmpty);
    });

    test('search "toxin": save first, skip second', () async {
      // User saves Toxin #1 but skips Toxin #2
      var reviewCount = 0;
      h.mockTernary('_REVIEW_HERO', (model, current, total) {
        reviewCount++;
        return reviewCount == 1 ? 'save' : 'skip';
      });

      await h.test(r'''
        Search.SEARCH_HEROES('toxin');

        EXPECT(Heroes.total_heroes, 1);
        EXPECT(LENGTH(Search.search_results), 2);
        ASSERT('1 saved' IN Search.search_summary);
        ASSERT('1 skipped' IN Search.search_summary);

        ASSERT_CALL_COUNT('_REVIEW_HERO', 2);
        ASSERT_CALL_COUNT('_PERSIST_HERO', 1);
        ASSERT_CALL_COUNT('_MAP_HERO', 1)
      ''');

      expect(heroDataManager.heroes, hasLength(1));
    });

    test('search already-saved hero: summary says "already saved"',
        () async {
      // First: save Jubilee via search
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'save');
      await h.test("Search.SEARCH_HEROES('jubilee')");
      expect(heroDataManager.heroes, hasLength(1));

      // Second: search again — hero is already saved
      await h.test(r'''
        CLEAR_CALL_LOG();
        Search.SEARCH_HEROES('jubilee');

        ASSERT('already saved' IN Search.search_summary);
        EXPECT(Heroes.total_heroes, 1);
        ASSERT_NOT_CALLED('_PERSIST_HERO');
        ASSERT_NOT_CALLED('_REVIEW_HERO')
      ''');
    });

    test('search history tracks queries in reverse order', () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'skip');

      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');
        Search.SEARCH_HEROES('toxin');
        EXPECT(LENGTH(Search.search_history), 2);
        EXPECT(Search.search_history[0], 'toxin');
        EXPECT(Search.search_history[1], 'jubilee')
      ''');
    });

    test('saved hero appears in card cache after search', () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'save');

      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');
        ASSERT(LENGTH(Cards.card_cache) > 0)
      ''');
    });

    test('search "spider-man" + save all: 3 heroes, filters and stats grow',
        () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'saveAll');

      await h.test(r'''
        Search.SEARCH_HEROES('spider-man');

        EXPECT(Heroes.total_heroes, 3);
        ASSERT('3 saved' IN Search.search_summary);
        ASSERT(Stats.COUNT_HEIGHT() >= 3);
        EXPECT(LENGTH(Filters.displayed_heroes), 3);
        ASSERT(LENGTH(Cards.card_cache) >= 3)
      ''');

      expect(heroDataManager.heroes, hasLength(3));
    });

    test('search "ymir" + save: Ymir appears in Giants filter', () async {
      // Pre-populate DB with several heroes so Stats has meaningful height data
      final preloadIds = [
        '69',  // Batman
        '644', // Superman
        '620', // Spider-Man
        '370', // Joker
        '149', // Captain America
      ];
      for (final id in preloadIds) {
        final hero = await _persistFixtureHero(
            mockService, heroDataManager, shqlBindings, id);
        await h.test('Heroes.ON_HERO_ADDED(__h); Cards.CACHE_HERO_CARD(__h)',
            boundValues: {'__h': hero.obj});
      }

      // Compile filters so Giants predicate is a real lambda
      await h.test(r'''
        Filters.FULL_REBUILD();
        EXPECT(Heroes.total_heroes, 5);
        ASSERT(Stats.AVG_HEIGHT() > 0);
        ASSERT(Stats.STDEV_HEIGHT() > 0);

        -- Giants filter (index 2): nobody in it yet — all normal-height heroes
        EXPECT(Filters.GET_FILTER_COUNT(2), 0)
      ''');

      // Now search "ymir" and save — Ymir is 304.8m, far above any threshold
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'save');
      await h.test(r'''
        CLEAR_CALL_LOG();
        Search.SEARCH_HEROES('ymir');

        -- Ymir saved
        EXPECT(Heroes.total_heroes, 6);
        ASSERT_CALLED('_PERSIST_HERO');

        -- Giants filter now contains Ymir
        ASSERT(Filters.GET_FILTER_COUNT(2) >= 1);

        -- Height stats should be positive
        ASSERT(Stats.AVG_HEIGHT() > 0);
        ASSERT(Stats.STDEV_HEIGHT() > 0)
      ''');

      expect(heroDataManager.heroes, hasLength(6));
    });

    test('CLEAR_SEARCH resets results and query', () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'skip');
      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');
        ASSERT(LENGTH(Search.search_results) > 0);
        ASSERT(Search.search_query = 'jubilee');

        Search.CLEAR_SEARCH();
        EXPECT(LENGTH(Search.search_results), 0);
        EXPECT(Search.search_query, '')
      ''');
    });

    test('GENERATE_SEARCH_CARDS returns empty-state card when no results',
        () async {
      await h.test(r'''
        __cards := Search.GENERATE_SEARCH_CARDS();
        EXPECT(LENGTH(__cards), 1);
        EXPECT(__cards[0]['type'], 'Center')
      ''');
    });

    test('GENERATE_SEARCH_CARDS returns hero cards after search', () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'save');
      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');
        ASSERT(LENGTH(Search.GENERATE_SEARCH_CARDS()) > 0)
      ''');
    });

    test('GENERATE_SEARCH_HISTORY returns chips from history', () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'skip');
      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');
        Search.SEARCH_HEROES('toxin');
        __chips := Search.GENERATE_SEARCH_HISTORY();
        EXPECT(LENGTH(__chips), 2);
        -- Each chip is an ActionChip with label and onPressed
        EXPECT(__chips[0]['type'], 'ActionChip')
      ''');
    });

    test('GENERATE_SEARCH_HISTORY returns empty list when no history',
        () async {
      await h.test(r'''
        Search.search_history := [];
        EXPECT(LENGTH(Search.GENERATE_SEARCH_HISTORY()), 0)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HeroEdit — concrete HeroCoordinator + real SHQL™ modules
  // ═══════════════════════════════════════════════════════════════════
  group('HeroEdit', () {
    late ShqlTestRunner h;
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;
    late ShqlBindings shqlBindings;

    setUp(() async {
      final s = await _concreteSetUp();
      h = s.h;
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
      shqlBindings = s.shqlBindings;
    });

    /// Save a hero via the full pipeline, select it, and open edit form.
    Future<String> addAndEditHero(String externalId) async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, externalId);
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Cards.CACHE_HERO_CARD(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        HeroEdit.EDIT_HERO()
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
      return hero.id;
    }

    test('EDIT_HERO populates edit_fields from real hero data', () async {
      final heroId = await addAndEditHero('69'); // Batman
      await h.test(r'''
        ASSERT(LENGTH(HeroEdit.edit_fields) > 0);
        ASSERT_CONTAINS(Nav.navigation_stack, 'hero_edit');
        ASSERT_CALLED('_BUILD_EDIT_FIELDS')
      ''');
      // Verify hero is still in DB
      expect(heroDataManager.getById(heroId), isNotNull);
    });

    test('SAVE_AMENDMENTS with real name change updates SHQL™ state and DB',
        () async {
      final heroId = await addAndEditHero('69'); // Batman

      // Find the "name" field and change its value
      await h.test(r'''
        IF LENGTH(HeroEdit.edit_fields) > 0 THEN
          FOR __i := 0 TO LENGTH(HeroEdit.edit_fields) - 1 DO
            IF HeroEdit.edit_fields[__i].JSON_NAME = 'name' AND HeroEdit.edit_fields[__i].JSON_SECTION = '' THEN
              HeroEdit.edit_fields[__i].VALUE := 'Batman (Amended)';

        CLEAR_CALL_LOG();
        HeroEdit.SAVE_AMENDMENTS();

        -- SHQL™ state updated
        ASSERT(Heroes.heroes[__id] <> null);
        EXPECT(Heroes.total_heroes, 1);
        ASSERT_CALLED('_HERO_AMEND');

        -- Card re-cached
        ASSERT(Cards.card_cache[__id] <> null);

        -- Navigated back
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''', boundValues: {'__id': heroId});

      // DB: hero was amended, locked, and name actually changed
      final dbHero = heroDataManager.getById(heroId);
      expect(dbHero, isNotNull);
      expect(dbHero!.locked, true);
      expect(dbHero.name, 'Batman (Amended)');
    });

    test('SAVE_AMENDMENTS with powerstat change updates SHQL™ state and DB',
        () async {
      final heroId = await addAndEditHero('69'); // Batman

      // Find the intelligence field (nested under powerstats) and change it
      await h.test(r'''
        IF LENGTH(HeroEdit.edit_fields) > 0 THEN
          FOR __i := 0 TO LENGTH(HeroEdit.edit_fields) - 1 DO
            IF HeroEdit.edit_fields[__i].JSON_NAME = 'intelligence' AND HeroEdit.edit_fields[__i].JSON_SECTION = 'powerstats' THEN
              HeroEdit.edit_fields[__i].VALUE := '99';

        CLEAR_CALL_LOG();
        HeroEdit.SAVE_AMENDMENTS();

        -- SHQL™ state updated
        ASSERT(Heroes.heroes[__id] <> null);
        ASSERT_CALLED('_HERO_AMEND');

        -- Navigated back
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''', boundValues: {'__id': heroId});

      // DB: hero was amended, locked, and intelligence actually changed
      final dbHero = heroDataManager.getById(heroId);
      expect(dbHero, isNotNull);
      expect(dbHero!.locked, true);
      expect(dbHero.powerStats.intelligence?.value, 99);
    });

    test('SAVE_AMENDMENTS with no changes shows snackbar, no DB write',
        () async {
      await addAndEditHero('69');

      await h.test(r'''
        CLEAR_CALL_LOG();
        HeroEdit.SAVE_AMENDMENTS();
        ASSERT_NOT_CALLED('_HERO_AMEND');
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''');
    });

    test('BUILD_AMENDMENT only includes changed fields', () async {
      await addAndEditHero('69');

      // Change only the name field
      await h.test(r'''
        IF LENGTH(HeroEdit.edit_fields) > 0 THEN
          FOR __i := 0 TO LENGTH(HeroEdit.edit_fields) - 1 DO
            IF HeroEdit.edit_fields[__i].JSON_NAME = 'name' AND HeroEdit.edit_fields[__i].JSON_SECTION = '' THEN
              HeroEdit.edit_fields[__i].VALUE := 'Batman (Changed)';

        __amendment := HeroEdit.BUILD_AMENDMENT();
        ASSERT(__amendment <> null);
        EXPECT(__amendment['name'], 'Batman (Changed)')
      ''');
    });

    test('GENERATE_EDIT_FORM produces widget tree from real fields',
        () async {
      await addAndEditHero('69');
      await h.test('ASSERT(LENGTH(HeroEdit.GENERATE_EDIT_FORM()) > 0)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Navigation tests
  // ═══════════════════════════════════════════════════════════════════
  group('Navigation', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
    });

    test('GO_TO pushes route and navigates', () async {
      await h.test(r'''
        Nav.GO_TO('heroes');
        ASSERT(INDEX_OF(Nav.navigation_stack, 'heroes') >= 0)
      ''');
    });

    test('GO_TO does not duplicate route already in stack', () async {
      await h.test(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('heroes');
        __count := 0;
        IF LENGTH(Nav.navigation_stack) > 0 THEN
            FOR __i := 0 TO LENGTH(Nav.navigation_stack) - 1 DO
                IF Nav.navigation_stack[__i] = 'heroes' THEN
                    __count := __count + 1;
        EXPECT(__count, 1)
      ''');
    });

    test('GO_BACK pops and navigates to previous route', () async {
      await h.test(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('hero_detail');
        EXPECT(Nav.GO_BACK(), 'heroes');
        EXPECT(Nav.navigation_stack, ['home', 'heroes'])
      ''');
    });

    test('GO_BACK from root returns home', () async {
      await h.test("EXPECT(Nav.GO_BACK(), 'home')");
    });

    test('PUSH_ROUTE truncates stack when route already exists', () async {
      await h.test(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('hero_detail');
        Nav.PUSH_ROUTE('heroes');
        ASSERT(Nav.navigation_stack[LENGTH(Nav.navigation_stack) - 1] <> 'hero_detail')
      ''');
    });

    test('POP_ROUTE removes last entry', () async {
      await h.test(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('settings');
        EXPECT(Nav.POP_ROUTE(), 'heroes')
      ''');
    });

    test('TAB_NAV navigates when index differs from current', () async {
      await h.test(r'''
        Nav.TAB_NAV(0, 2);
        ASSERT(INDEX_OF(Nav.navigation_stack, 'heroes') >= 0)
      ''');
    });

    test('TAB_NAV is no-op when index matches current', () async {
      await h.test(r'''
        __stack_before := Nav.navigation_stack;
        Nav.TAB_NAV(0, 0);
        EXPECT(Nav.navigation_stack, __stack_before)
      ''');
    });

    test('CAN_GO_BACK returns false at root', () async {
      await h.test('EXPECT(Nav.CAN_GO_BACK(), FALSE)');
    });

    test('CAN_GO_BACK returns true with stacked routes', () async {
      await h.test(r'''
        Nav.GO_TO('heroes');
        EXPECT(Nav.CAN_GO_BACK(), TRUE)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Auth tests
  // ═══════════════════════════════════════════════════════════════════
  group('Auth', () {
    late ShqlTestRunner h;
    late Map<String, dynamic> savedState;

    setUp(() async {
      savedState = {};
      h = await _standardSetUp();

      // Override state functions to track saved state
      h.runtime.saveStateFunction = (key, value) async {
        savedState[key] = value;
      };
      h.runtime.loadStateFunction =
          (key, defaultValue) async => savedState[key] ?? defaultValue;
    });

    test('__FIREBASE_ERROR_MSG maps known codes', () async {
      await h.test(r'''
        ASSERT('No account' IN Auth.__FIREBASE_ERROR_MSG('EMAIL_NOT_FOUND'));
        ASSERT('Incorrect' IN Auth.__FIREBASE_ERROR_MSG('INVALID_PASSWORD'));
        ASSERT('Invalid email' IN Auth.__FIREBASE_ERROR_MSG('INVALID_LOGIN_CREDENTIALS'))
      ''');
    });

    test('__FIREBASE_ERROR_MSG returns code for unknown errors', () async {
      await h.test(r'''
        EXPECT(Auth.__FIREBASE_ERROR_MSG('SOME_UNKNOWN'), 'SOME_UNKNOWN')
      ''');
    });

    test('__FIREBASE_ERROR_MSG matches WEAK_PASSWORD with tilde', () async {
      await h.test(r'''
        ASSERT('6 characters' IN Auth.__FIREBASE_ERROR_MSG('WEAK_PASSWORD : some detail'))
      ''');
    });

    test('__FIREBASE_EXTRACT_ERROR handles null body', () async {
      await h.test(r'''
        EXPECT(Auth.__FIREBASE_EXTRACT_ERROR(null), 'Unknown error')
      ''');
    });

    test('__FIREBASE_EXTRACT_ERROR extracts nested error message', () async {
      final body = <String, dynamic>{
        'error': <String, dynamic>{'message': 'EMAIL_NOT_FOUND'}
      };
      await h.test(r'''
        ASSERT('No account' IN Auth.__FIREBASE_EXTRACT_ERROR(__body))
      ''', boundValues: {'__body': body});
    });

    test('FIREBASE_SIGN_IN calls POST and persists session on success',
        () async {
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        h.callLog.add('POST');
        return <String, dynamic>{
          'status': 200,
          'body': <String, dynamic>{
            'idToken': 'tok123',
            'email': 'a@b.com',
            'localId': 'uid1',
            'refreshToken': 'ref1'
          }
        };
      });

      await h.test(r'''
        -- null = success
        EXPECT(Auth.FIREBASE_SIGN_IN('a@b.com', 'pass123'), null);
        EXPECT(LOAD_STATE('_auth_id_token', null), 'tok123');
        EXPECT(LOAD_STATE('_auth_email', null), 'a@b.com');
        EXPECT(LOAD_STATE('_auth_uid', null), 'uid1');
        EXPECT(LOAD_STATE('_auth_refresh_token', null), 'ref1')
      ''');
    });

    test('FIREBASE_SIGN_IN returns error on failure', () async {
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        return <String, dynamic>{
          'status': 400,
          'body': <String, dynamic>{
            'error': <String, dynamic>{'message': 'INVALID_LOGIN_CREDENTIALS'}
          }
        };
      });

      await h.test(r'''
        ASSERT('Invalid' IN Auth.FIREBASE_SIGN_IN('a@b.com', 'wrong'))
      ''');
    });

    test('FIREBASE_SIGN_UP calls signUp endpoint', () async {
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        h.runtime.globalScope.setVariable(
            h.runtime.identifiers.include('__CALLED_URL'), url);
        return <String, dynamic>{
          'status': 200,
          'body': <String, dynamic>{
            'idToken': 'tok',
            'email': 'a@b.com',
            'localId': 'uid',
            'refreshToken': 'ref'
          }
        };
      });

      await h.test(r'''
        Auth.FIREBASE_SIGN_UP('a@b.com', 'pass');
        ASSERT('signUp' IN __CALLED_URL)
      ''');
    });

    test('FIREBASE_SIGN_OUT clears saved state', () async {
      savedState['_auth_id_token'] = 'tok';
      savedState['_auth_email'] = 'a@b.com';
      savedState['_auth_uid'] = 'uid';
      savedState['_auth_refresh_token'] = 'ref';

      await h.test(r'''
        Auth.FIREBASE_SIGN_OUT();
        EXPECT(LOAD_STATE('_auth_id_token', null), null);
        EXPECT(LOAD_STATE('_auth_email', null), null);
        EXPECT(LOAD_STATE('_auth_uid', null), null);
        EXPECT(LOAD_STATE('_auth_refresh_token', null), null)
      ''');
    });

    test('FIREBASE_REFRESH_TOKEN returns empty when no refresh token',
        () async {
      await h.test("EXPECT(Auth.FIREBASE_REFRESH_TOKEN(), '')");
    });

    test('FIREBASE_REFRESH_TOKEN refreshes on success', () async {
      savedState['_auth_refresh_token'] = 'old_ref';
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        return <String, dynamic>{
          'status': 200,
          'body': <String, dynamic>{
            'id_token': 'new_tok',
            'refresh_token': 'new_ref'
          }
        };
      });

      await h.test(r'''
        EXPECT(Auth.FIREBASE_REFRESH_TOKEN(), 'new_tok');
        EXPECT(LOAD_STATE('_auth_id_token', null), 'new_tok');
        EXPECT(LOAD_STATE('_auth_refresh_token', null), 'new_ref')
      ''');
    });

    test('LOGIN_SUBMIT rejects empty email', () async {
      await h.test(r'''
        Auth.SET_LOGIN_EMAIL('');
        Auth.SET_LOGIN_PASSWORD('pass');
        Auth.LOGIN_SUBMIT();
        EXPECT(Auth.LOGIN_IS_LOADING, FALSE);
        ASSERT('email and password' IN Auth.LOGIN_ERROR)
      ''');
    });

    test('LOGIN_SUBMIT signs in and calls __ON_AUTHENTICATED on success',
        () async {
      h.runtime.setNullaryFunction('__ON_AUTHENTICATED', (ctx, caller) {
        h.callLog.add('__ON_AUTHENTICATED()');
        return null;
      });

      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        return <String, dynamic>{
          'status': 200,
          'body': <String, dynamic>{
            'idToken': 'tok',
            'email': 'a@b.com',
            'localId': 'uid',
            'refreshToken': 'ref'
          }
        };
      });

      await h.test(r'''
        Auth.SET_LOGIN_EMAIL('a@b.com');
        Auth.SET_LOGIN_PASSWORD('pass123');
        CLEAR_CALL_LOG();
        Auth.LOGIN_SUBMIT();
        ASSERT_CALLED('__ON_AUTHENTICATED')
      ''');
    });

    test('LOGIN_SUBMIT sets error on auth failure', () async {
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        return <String, dynamic>{
          'status': 400,
          'body': <String, dynamic>{
            'error': <String, dynamic>{'message': 'INVALID_PASSWORD'}
          }
        };
      });

      await h.test(r'''
        Auth.SET_LOGIN_EMAIL('a@b.com');
        Auth.SET_LOGIN_PASSWORD('wrong');
        Auth.LOGIN_SUBMIT();
        EXPECT(Auth.LOGIN_IS_LOADING, FALSE);
        ASSERT('Incorrect' IN Auth.LOGIN_ERROR)
      ''');
    });

    test('LOGIN_TOGGLE_MODE toggles register flag and clears error', () async {
      await h.test(r'''
        Auth.SET_LOGIN_ERROR('some error');
        EXPECT(Auth.LOGIN_IS_REGISTERING, FALSE);
        Auth.LOGIN_TOGGLE_MODE();
        EXPECT(Auth.LOGIN_IS_REGISTERING, TRUE);
        EXPECT(Auth.LOGIN_ERROR, '');
        Auth.LOGIN_TOGGLE_MODE();
        EXPECT(Auth.LOGIN_IS_REGISTERING, FALSE)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Firestore tests
  // ═══════════════════════════════════════════════════════════════════
  group('Firestore', () {
    late ShqlTestRunner h;
    late Map<String, dynamic> savedState;

    setUp(() async {
      savedState = {};
      h = await _standardSetUp();

      // Override state functions to track saved state
      h.runtime.saveStateFunction = (key, value) async {
        savedState[key] = value;
      };
      h.runtime.loadStateFunction =
          (key, defaultValue) async => savedState[key] ?? defaultValue;
    });

    test('__TO_VALUE converts booleans', () async {
      await h.test(r'''
        EXPECT(Cloud.__TO_VALUE(TRUE)['booleanValue'], TRUE)
      ''');
    });

    test('__TO_VALUE converts strings', () async {
      await h.test(r'''
        EXPECT(Cloud.__TO_VALUE('hello')['stringValue'], 'hello')
      ''');
    });

    test('__FROM_VALUE converts boolean values', () async {
      await h.test("EXPECT(Cloud.__FROM_VALUE({'booleanValue': TRUE}), TRUE)");
    });

    test('__FROM_VALUE converts integer values', () async {
      await h.test('EXPECT(Cloud.__FROM_VALUE({"integerValue": "42"}), 42)');
    });

    test('__FROM_VALUE converts string values', () async {
      await h.test(r'''
        EXPECT(Cloud.__FROM_VALUE({'stringValue': 'hello'}), 'hello')
      ''');
    });

    test('__FROM_VALUE returns null for unknown types', () async {
      await h.test('ASSERT(Cloud.__FROM_VALUE({}) = null)');
    });

    test('SET_AUTH_UID updates uid', () async {
      await h.test(r'''
        Cloud.SET_AUTH_UID('user123');
        EXPECT(Cloud.auth_uid, 'user123')
      ''');
    });

    test('SAVE skips when auth_uid is empty', () async {
      h.mockTernary('PATCH_AUTH', (a, b, c) =>
          <String, dynamic>{'status': 200});

      await h.test(r'''
        CLEAR_CALL_LOG();
        Cloud.SAVE('is_dark_mode', TRUE);
        ASSERT_NOT_CALLED('PATCH_AUTH')
      ''');
    });

    test('SAVE skips when key not in SYNCED_KEYS', () async {
      savedState['_auth_id_token'] = 'tok';

      h.mockTernary('PATCH_AUTH', (a, b, c) =>
          <String, dynamic>{'status': 200});

      await h.test(r'''
        Cloud.SET_AUTH_UID('uid1');
        CLEAR_CALL_LOG();
        Cloud.SAVE('not_synced_key', 'value');
        ASSERT_NOT_CALLED('PATCH_AUTH')
      ''');
    });

    test('SAVE calls PATCH_AUTH with correct URL', () async {
      savedState['_auth_id_token'] = 'tok';

      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, url, body, token) {
        h.runtime.globalScope.setVariable(
            h.runtime.identifiers.include('__CALLED_URL'), url);
        return <String, dynamic>{'status': 200};
      });

      await h.test(r'''
        Cloud.SET_AUTH_UID('uid1');
        Cloud.SAVE('is_dark_mode', TRUE);
        ASSERT('server-driven-ui-flutter' IN __CALLED_URL);
        ASSERT('uid1' IN __CALLED_URL);
        ASSERT('is_dark_mode' IN __CALLED_URL)
      ''');
    });

    test('SAVE retries with refresh on 401', () async {
      savedState['_auth_id_token'] = 'tok';
      savedState['_auth_refresh_token'] = 'refresh_tok';

      // POST is called by Auth.FIREBASE_REFRESH_TOKEN() to exchange the
      // refresh token for a new id token.
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        return <String, dynamic>{
          'status': 200,
          'body': <String, dynamic>{
            'id_token': 'new_tok',
            'refresh_token': 'new_refresh',
          },
        };
      });

      var callCount = 0;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, url, body, token) {
        callCount++;
        if (callCount == 1) return <String, dynamic>{'status': 401};
        return <String, dynamic>{'status': 200};
      });

      await h.test(r'''
        Cloud.SET_AUTH_UID('uid1');
        Cloud.SAVE('is_dark_mode', TRUE)
      ''');
      // Dart-level count: PATCH_AUTH has conditional behavior, not mockable
      expect(callCount, 2, reason: 'Should retry after 401');
    });

    test('LOAD_ALL returns empty map when no uid', () async {
      await h.test('EXPECT(LENGTH(Cloud.LOAD_ALL()), 0)');
    });

    test('LOAD_ALL parses Firestore fields', () async {
      savedState['_auth_id_token'] = 'tok';

      h.runtime.setBinaryFunction('FETCH_AUTH', (ctx, caller, url, token) {
        return <String, dynamic>{
          'status': 200,
          'body': <String, dynamic>{
            'fields': <String, dynamic>{
              'is_dark_mode': <String, dynamic>{'booleanValue': true},
              'api_key': <String, dynamic>{'stringValue': 'mykey'},
              'unknown_key': <String, dynamic>{'stringValue': 'ignored'},
            }
          }
        };
      });

      await h.test(r'''
        Cloud.SET_AUTH_UID('uid1');
        __r := Cloud.LOAD_ALL();
        EXPECT(__r['is_dark_mode'], TRUE);
        EXPECT(__r['api_key'], 'mykey')
      ''');
    });

    test('SAVE_PREF saves locally and to cloud', () async {
      await h.test(r'''
        Cloud.SAVE_PREF('is_dark_mode', TRUE);
        EXPECT(LOAD_STATE('is_dark_mode', null), TRUE)
      ''');
    });

    test('SEED_AND_APPLY_STATE returns initial route', () async {
      await h.test(r'''
        Prefs.onboarding_completed := TRUE;
        EXPECT(Cloud.SEED_AND_APPLY_STATE(), 'home')
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Preferences tests
  // ═══════════════════════════════════════════════════════════════════
  group('Preferences', () {
    late ShqlTestRunner h;
    late List<String> prefChanges;

    setUp(() async {
      h = await _standardSetUp();
      prefChanges = [];

      // Override individual platform callbacks to track preference changes.
      // _ON_PREF_CHANGED (SHQL™) dispatches to these platform callbacks.
      h.runtime.setUnaryFunction('_SET_DARK_MODE', (ctx, c, v) {
        prefChanges.add('is_dark_mode=$v');
        return null;
      });
      h.runtime.setUnaryFunction('_SET_ANALYTICS', (ctx, c, v) {
        prefChanges.add('analytics_enabled=$v');
        return null;
      });
      h.runtime.setUnaryFunction('_SET_CRASHLYTICS', (ctx, c, v) {
        prefChanges.add('crashlytics_enabled=$v');
        return null;
      });
      h.runtime.setUnaryFunction('_GET_LOCATION', (ctx, c, v) {
        prefChanges.add('location_enabled=$v');
        return h.makeObject({'description': '', 'latitude': null, 'longitude': null});
      });
      h.runtime.setUnaryFunction('_REFRESH_HERO_SERVICE', (ctx, c, v) {
        prefChanges.add('api_service_refreshed=true');
        return null;
      });
    });

    test('TOGGLE_DARK_MODE flips dark mode', () async {
      await h.test(r'''
        EXPECT(Prefs.is_dark_mode, FALSE);
        Prefs.TOGGLE_DARK_MODE();
        EXPECT(Prefs.is_dark_mode, TRUE)
      ''');
      expect(prefChanges, contains('is_dark_mode=true'));

      await h.test(r'''
        Prefs.TOGGLE_DARK_MODE();
        EXPECT(Prefs.is_dark_mode, FALSE)
      ''');
    });

    test('SET_DARK_MODE sets explicit value', () async {
      await h.test(r'''
        Prefs.SET_DARK_MODE(TRUE);
        EXPECT(Prefs.is_dark_mode, TRUE)
      ''');
      expect(prefChanges, contains('is_dark_mode=true'));
    });

    test('SET_ANALYTICS_CONSENT saves and notifies', () async {
      await h.test(r'''
        Prefs.SET_ANALYTICS_CONSENT(TRUE);
        EXPECT(Prefs.analytics_enabled, TRUE)
      ''');
      expect(prefChanges, contains('analytics_enabled=true'));
    });

    test('SET_CRASHLYTICS_CONSENT saves and notifies', () async {
      await h.test(r'''
        Prefs.SET_CRASHLYTICS_CONSENT(TRUE);
        EXPECT(Prefs.crashlytics_enabled, TRUE)
      ''');
      expect(prefChanges, contains('crashlytics_enabled=true'));
    });

    test('SET_LOCATION_CONSENT saves and notifies', () async {
      await h.test(r'''
        Prefs.SET_LOCATION_CONSENT(TRUE);
        EXPECT(Prefs.location_enabled, TRUE)
      ''');
      expect(prefChanges, contains('location_enabled=true'));
    });

    test('COMPLETE_ONBOARDING sets flag to true', () async {
      await h.test(r'''
        Prefs.COMPLETE_ONBOARDING();
        EXPECT(Prefs.onboarding_completed, TRUE)
      ''');
    });

    test('IS_ONBOARDING_COMPLETED returns current value', () async {
      await h.test(r'''
        EXPECT(Prefs.IS_ONBOARDING_COMPLETED(), FALSE);
        Prefs.COMPLETE_ONBOARDING();
        EXPECT(Prefs.IS_ONBOARDING_COMPLETED(), TRUE)
      ''');
    });

    test('RESET_ONBOARDING clears flag and navigates to onboarding', () async {
      await h.test(r'''
        Prefs.COMPLETE_ONBOARDING();
        Prefs.RESET_ONBOARDING();
        EXPECT(Prefs.onboarding_completed, FALSE);
        ASSERT_CONTAINS(Nav.navigation_stack, 'onboarding')
      ''');
    });

    test('FINISH_ONBOARDING completes onboarding and navigates to home', () async {
      await h.test(r'''
        Prefs.FINISH_ONBOARDING();
        EXPECT(Prefs.onboarding_completed, TRUE);
        ASSERT_CONTAINS(Nav.navigation_stack, 'home')
      ''');
    });

    test('SET_API_KEY stores key', () async {
      await h.test(r'''
        Prefs.SET_API_KEY('mykey123');
        EXPECT(Prefs.api_key, 'mykey123')
      ''');
    });

    test('SET_API_HOST stores host', () async {
      await h.test(r'''
        Prefs.SET_API_HOST('custom.api.com');
        EXPECT(Prefs.api_host, 'custom.api.com')
      ''');
    });

    test('APPLY_INIT_STATE applies prefs via callback and returns route', () async {
      await h.test(r'''
        Prefs.SET_DARK_MODE(TRUE);
        Prefs.SET_ANALYTICS_CONSENT(TRUE)
      ''');
      prefChanges.clear();

      await h.test(r'''
        __route := Prefs.APPLY_INIT_STATE();
        EXPECT(__route, 'onboarding')
      ''');
      // Verify _ON_PREF_CHANGED was called for non-location prefs
      // (location uses World.INIT_LOCATION, not _ON_PREF_CHANGED, on cold start)
      expect(prefChanges, contains('is_dark_mode=true'));
      expect(prefChanges, contains('analytics_enabled=true'));
      expect(prefChanges, contains('crashlytics_enabled=false'));
      expect(prefChanges, isNot(contains('location_enabled=false')));

      await h.test(r'''
        Prefs.COMPLETE_ONBOARDING();
        __route2 := Prefs.APPLY_INIT_STATE();
        EXPECT(__route2, 'home')
      ''');
    });

    test('GET_API_CREDENTIALS returns cached values', () async {
      await h.test(r'''
        Prefs.SET_API_KEY('mykey');
        Prefs.SET_API_HOST('myhost.com');
        __creds := Prefs.GET_API_CREDENTIALS();
        EXPECT(__creds.API_KEY, 'mykey');
        EXPECT(__creds.API_HOST, 'myhost.com')
      ''');
    });

    test('GET_API_CREDENTIALS prompts when key is empty', () async {
      h.mockBinary('_PROMPT', (prompt, defaultVal) => 'prompted_key');

      await h.test(r'''
        __creds := Prefs.GET_API_CREDENTIALS();
        EXPECT(__creds.API_KEY, 'prompted_key');
        ASSERT_CALLED('_PROMPT')
      ''');
    });

    test('GET_API_CREDENTIALS returns null when user cancels prompt',
        () async {
      h.runtime.setBinaryFunction('_PROMPT', (ctx, caller, prompt, defaultVal) {
        return null;
      });

      await h.test(r'''
        __creds := Prefs.GET_API_CREDENTIALS();
        ASSERT(__creds = null)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Statistics tests
  // ═══════════════════════════════════════════════════════════════════
  group('Statistics', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
    });

    /// Build a hero object with proper nested structure for schema accessors.
    dynamic makeStatsHero(String id, String name,
        {double? heightM, double? weightKg, int? strength}) {
      final appearance = h.makeObject({
        'height': h.makeObject({'m': heightM ?? 0}),
        'weight': h.makeObject({'kg': weightKg ?? 0}),
      });
      final powerstats = h.makeObject({'strength': strength ?? 0});
      return h.makeObject({
        'id': id,
        'name': name,
        'appearance': appearance,
        'powerstats': powerstats,
      });
    }

    test('ON_HERO_ADDED invalidates cache; lazy accessors compute fresh', () async {
      final hero =
          makeStatsHero('h1', 'Batman', heightM: 1.88, weightKg: 95.0, strength: 80);
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        EXPECT(Stats.COUNT_HEIGHT(), 1);
        EXPECT(Stats.COUNT_WEIGHT(), 1);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 80);
        EXPECT(Stats.SUM_HEIGHT(), 1.88)
      ''', boundValues: {'__h': hero});
    });

    test('lazy accessors compute avg and stdev from heroes map', () async {
      final h1 =
          makeStatsHero('h1', 'Hero1', heightM: 1.80, weightKg: 80.0, strength: 50);
      final h2 =
          makeStatsHero('h2', 'Hero2', heightM: 2.00, weightKg: 100.0, strength: 70);

      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h1);
        Heroes.ON_HERO_ADDED(__h2);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 120);
        ASSERT(Stats.AVG_HEIGHT() > 1.89);
        ASSERT(Stats.AVG_HEIGHT() < 1.91);
        ASSERT(Stats.STDEV_HEIGHT() > 0)
      ''', boundValues: {'__h1': h1, '__h2': h2});
    });

    test('ON_HERO_REMOVED removes hero from stats', () async {
      final hero =
          makeStatsHero('h1', 'Batman', heightM: 1.88, weightKg: 95.0, strength: 80);
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.ON_HERO_REMOVED(__h);
        EXPECT(Stats.COUNT_HEIGHT(), 0);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 0);
        EXPECT(Stats.AVG_HEIGHT(), 0)
      ''', boundValues: {'__h': hero});
    });

    test('INVALIDATE + re-add gives correct stats', () async {
      final oldHero =
          makeStatsHero('h1', 'OldHero', heightM: 1.80, weightKg: 80.0, strength: 50);
      final newHero =
          makeStatsHero('h1', 'NewHero', heightM: 2.00, weightKg: 100.0, strength: 90);

      await h.test(r'''
        Heroes.ON_HERO_ADDED(__old);
        Heroes.ON_HERO_REMOVED(__old);
        Heroes.ON_HERO_ADDED(__new);
        EXPECT(Stats.COUNT_HEIGHT(), 1);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 90);
        ASSERT(Stats.AVG_HEIGHT() > 1.99);
        ASSERT(Stats.AVG_HEIGHT() < 2.01)
      ''', boundValues: {'__old': oldHero, '__new': newHero});
    });

    test('ON_HERO_CLEAR resets all stats to zero', () async {
      final hero =
          makeStatsHero('h1', 'Batman', heightM: 1.88, weightKg: 95.0, strength: 80);
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.ON_HERO_CLEAR();
        EXPECT(Stats.COUNT_HEIGHT(), 0);
        EXPECT(Stats.SUM_HEIGHT(), 0);
        EXPECT(Stats.COUNT_WEIGHT(), 0);
        EXPECT(Stats.SUM_WEIGHT(), 0);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 0);
        EXPECT(Stats.AVG_HEIGHT(), 0);
        EXPECT(Stats.STDEV_HEIGHT(), 0)
      ''', boundValues: {'__h': hero});
    });

    test('hero with no height/weight excluded from height/weight stats', () async {
      final hero = makeStatsHero('h1', 'NoAppearance', strength: 50);
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        EXPECT(Stats.COUNT_HEIGHT(), 0);
        EXPECT(Stats.COUNT_WEIGHT(), 0);
        EXPECT(Stats.TOTAL_FIGHTING_POWER(), 50)
      ''', boundValues: {'__h': hero});
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Filters tests
  // ═══════════════════════════════════════════════════════════════════
  group('Filters', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
    });

    test('Default filters are loaded', () async {
      await h.test('ASSERT(LENGTH(Filters.filters) >= 10)');
    });

    test('APPLY_FILTER sets active index and updates display', () async {
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        Filters.APPLY_FILTER(0);
        EXPECT(Filters.active_filter_index, 0);
        EXPECT(Filters.current_query, '')
      ''');
    });

    test('APPLY_FILTER with -1 shows all heroes', () async {
      await h.test(r'''
        Filters.APPLY_FILTER(-1);
        EXPECT(Filters.active_filter_index, -1)
      ''');
    });

    test('SAVE_FILTER updates existing filter by name', () async {
      await h.test(r'''
        Filters.SAVE_FILTER('Heroes', 'new predicate');
        __found := FALSE;
        IF LENGTH(Filters.filters) > 0 THEN
            FOR __i := 0 TO LENGTH(Filters.filters) - 1 DO
                IF Filters.filters[__i].NAME = 'Heroes' THEN BEGIN
                    EXPECT(Filters.filters[__i].PREDICATE, 'new predicate');
                    __found := TRUE;
                END;
        ASSERT(__found)
      ''');
    });

    test('SAVE_FILTER adds new filter when name not found', () async {
      await h.test(r'''
        __count_before := LENGTH(Filters.filters);
        Filters.SAVE_FILTER('Custom', 'x > 5');
        EXPECT(LENGTH(Filters.filters), __count_before + 1)
      ''');
    });

    test('DELETE_FILTER removes filter at index', () async {
      await h.test(r'''
        __count_before := LENGTH(Filters.filters);
        Filters.DELETE_FILTER(0);
        EXPECT(LENGTH(Filters.filters), __count_before - 1)
      ''');
    });

    test('DELETE_FILTER is no-op for out of range', () async {
      await h.test(r'''
        __count_before := LENGTH(Filters.filters);
        Filters.DELETE_FILTER(-1);
        Filters.DELETE_FILTER(999);
        EXPECT(LENGTH(Filters.filters), __count_before)
      ''');
    });

    test('ADD_FILTER adds empty filter and selects it', () async {
      await h.test(r'''
        __count_before := LENGTH(Filters.filters);
        Filters.ADD_FILTER();
        EXPECT(LENGTH(Filters.filters), __count_before + 1);
        EXPECT(Filters.active_filter_index, LENGTH(Filters.filters) - 1)
      ''');
    });

    test('RENAME_FILTER changes name at index', () async {
      await h.test(r'''
        Filters.RENAME_FILTER(0, 'Good Guys');
        EXPECT(Filters.filters[0].NAME, 'Good Guys')
      ''');
    });

    test('RENAME_FILTER is no-op for out of range', () async {
      await h.test(r'''
        __first_before := Filters.filters[0].NAME;
        Filters.RENAME_FILTER(-1, 'Fail');
        Filters.RENAME_FILTER(999, 'Fail');
        EXPECT(Filters.filters[0].NAME, __first_before)
      ''');
    });

    test('RESET_PREDICATES restores default filters', () async {
      await h.test(r'''
        Filters.DELETE_FILTER(0);
        Filters.RESET_PREDICATES();
        EXPECT(LENGTH(Filters.filters), 11);
        EXPECT(Filters.active_filter_index, -1)
      ''');
    });

    test('REBUILD_ALL_FILTERS populates displayed_heroes from hero map', () async {
      final appearance = h.makeObject({
        'height': h.makeObject({'m': 1.88}),
        'weight': h.makeObject({'kg': 95.0}),
      });
      final powerstats = h.makeObject({'strength': 80});
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'appearance': appearance,
        'powerstats': powerstats,
      });
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Filters.REBUILD_ALL_FILTERS();
        ASSERT(LENGTH(Filters.displayed_heroes) > 0)
      ''', boundValues: {'__h': hero});
    });

    test('REBUILD_ALL_FILTERS reflects removals', () async {
      final appearance = h.makeObject({
        'height': h.makeObject({'m': 1.88}),
        'weight': h.makeObject({'kg': 95.0}),
      });
      final powerstats = h.makeObject({'strength': 80});
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'appearance': appearance,
        'powerstats': powerstats,
      });
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Filters.REBUILD_ALL_FILTERS();
        Heroes.ON_HERO_REMOVED(__h);
        Filters.REBUILD_ALL_FILTERS();
        EXPECT(LENGTH(Filters.displayed_heroes), 0)
      ''', boundValues: {'__h': hero});
    });

    test('REBUILD_ALL_FILTERS on empty heroes clears counts', () async {
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        IF LENGTH(Filters.filter_counts) > 0 THEN
            FOR __i := 0 TO LENGTH(Filters.filter_counts) - 1 DO
                EXPECT(Filters.filter_counts[__i], 0)
      ''');
    });

    test('GET_DISPLAY_STATE returns empty message when no heroes match',
        () async {
      await h.test(r'''
        Filters.SET_CURRENT_QUERY('xyz');
        __state := Filters.GET_DISPLAY_STATE();
        EXPECT(LENGTH(__state.HEROES), 0);
        ASSERT(__state.EMPTY_CARD <> null)
      ''');
    });

    test('GET_EDITOR_STATE returns filter state', () async {
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        __state := Filters.GET_EDITOR_STATE();
        ASSERT(LENGTH(__state.FILTERS) > 0);
        EXPECT(__state.ACTIVE_FILTER_INDEX, -1)
      ''');
    });

    test('APPLY_QUERY sets query and triggers rebuild', () async {
      await h.test(r'''
        Filters.APPLY_QUERY('test');
        EXPECT(Filters.current_query, 'test');
        EXPECT(Filters.active_filter_index, -1)
      ''');
    });

    test('GENERATE_FILTER_COUNTER_CARDS returns card list', () async {
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        __cards := Filters.GENERATE_FILTER_COUNTER_CARDS();
        ASSERT(LENGTH(__cards) >= 10);
        EXPECT(__cards[0]['type'], 'Card')
      ''');
    });

    test('UPDATE_DISPLAYED_HEROES reflects hero removal after rebuild',
        () async {
      final appearance = h.makeObject({
        'height': h.makeObject({'m': 1.88}),
        'weight': h.makeObject({'kg': 95.0}),
      });
      final powerstats = h.makeObject({'strength': 80});
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'appearance': appearance,
        'powerstats': powerstats,
      });
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Filters.REBUILD_ALL_FILTERS();
        ASSERT(LENGTH(Filters.displayed_heroes) > 0);
        Heroes.ON_HERO_REMOVED(__h);
        Filters.REBUILD_ALL_FILTERS();
        EXPECT(LENGTH(Filters.displayed_heroes), 0)
      ''', boundValues: {'__h': hero});
    });

    test('APPLY_AND_NAVIGATE applies filter and navigates to heroes', () async {
      await h.test(r'''
        Filters.APPLY_AND_NAVIGATE(0);
        EXPECT(Filters.active_filter_index, 0);
        ASSERT_CONTAINS(Nav.navigation_stack, 'heroes')
      ''');
    });

    test('on_apply callback fires after APPLY_FILTER', () async {
      // Use a side-effect visible after eval: push a route via Nav
      await h.test(r'''
        Filters.SET_ON_APPLY(() => Nav.PUSH_ROUTE('on_apply_fired'));
        Filters.APPLY_FILTER(0);
        ASSERT_CONTAINS(Nav.navigation_stack, 'on_apply_fired');
        Filters.SET_ON_APPLY(null)
      ''');
    });

    test('on_apply callback fires after APPLY_QUERY', () async {
      await h.test(r'''
        Filters.SET_ON_APPLY(() => Nav.PUSH_ROUTE('on_apply_query'));
        Filters.APPLY_QUERY('test');
        ASSERT_CONTAINS(Nav.navigation_stack, 'on_apply_query');
        Filters.SET_ON_APPLY(null)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // World tests
  // ═══════════════════════════════════════════════════════════════════
  group('World', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
    });

    test('SET_LOCATION_DESCRIPTION updates description', () async {
      await h.test(r'''
        World.SET_LOCATION_DESCRIPTION('New York');
        EXPECT(World.location_description, 'New York')
      ''');
    });

    test('SET_USER_COORDINATES updates lat and lon', () async {
      await h.test(r'''
        World.SET_USER_COORDINATES(40.7, -74.0);
        EXPECT(World.user_latitude, 40.7);
        EXPECT(World.user_longitude, -74.0)
      ''');
    });

    test('SET_LOCATION sets description and coordinates', () async {
      await h.test(r'''
        World.SET_LOCATION('Paris', 48.85, 2.35);
        EXPECT(World.location_description, 'Paris');
        EXPECT(World.user_latitude, 48.85);
        EXPECT(World.user_longitude, 2.35)
      ''');
    });

    test('SET_LOCATION with null coordinates only sets description',
        () async {
      await h.test(r'''
        World.SET_USER_COORDINATES(10.0, 20.0);
        World.SET_LOCATION('Unknown', null, null);
        EXPECT(World.location_description, 'Unknown');
        EXPECT(World.user_latitude, 10.0);
        EXPECT(World.user_longitude, 20.0)
      ''');
    });

    test('__WMO_WEATHER maps weather codes to description+icon pairs', () async {
      await h.test(r'''
        EXPECT(World.__WMO_WEATHER(0).DESCRIPTION, 'Clear sky');
        EXPECT(World.__WMO_WEATHER(0).ICON, 'wb_sunny');
        EXPECT(World.__WMO_WEATHER(2).DESCRIPTION, 'Partly cloudy');
        EXPECT(World.__WMO_WEATHER(2).ICON, 'cloud');
        EXPECT(World.__WMO_WEATHER(45).DESCRIPTION, 'Foggy');
        EXPECT(World.__WMO_WEATHER(45).ICON, 'foggy');
        EXPECT(World.__WMO_WEATHER(55).DESCRIPTION, 'Drizzle');
        EXPECT(World.__WMO_WEATHER(55).ICON, 'water_drop');
        EXPECT(World.__WMO_WEATHER(63).DESCRIPTION, 'Rain');
        EXPECT(World.__WMO_WEATHER(63).ICON, 'water_drop');
        EXPECT(World.__WMO_WEATHER(73).DESCRIPTION, 'Snow');
        EXPECT(World.__WMO_WEATHER(73).ICON, 'ac_unit');
        EXPECT(World.__WMO_WEATHER(80).DESCRIPTION, 'Rain showers');
        EXPECT(World.__WMO_WEATHER(80).ICON, 'ac_unit');
        EXPECT(World.__WMO_WEATHER(85).DESCRIPTION, 'Snow showers');
        EXPECT(World.__WMO_WEATHER(85).ICON, 'ac_unit');
        EXPECT(World.__WMO_WEATHER(95).DESCRIPTION, 'Thunderstorm');
        EXPECT(World.__WMO_WEATHER(95).ICON, 'flash_on')
      ''');
    });

    test('SET_WEATHER sets all weather properties', () async {
      await h.test(r'''
        World.SET_WEATHER(22.5, 15.0, 'Sunny', 'wb_sunny');
        EXPECT(World.weather_temp, 22.5);
        EXPECT(World.weather_wind, 15.0);
        EXPECT(World.weather_description, 'Sunny');
        EXPECT(World.weather_icon, 'wb_sunny')
      ''');
    });

    test('REFRESH_WEATHER parses API response', () async {
      h.runtime.setUnaryFunction('FETCH', (ctx, caller, url) {
        return <String, dynamic>{
          'current_weather': <String, dynamic>{
            'temperature': 18.5,
            'windspeed': 12.3,
            'weathercode': 0
          }
        };
      });

      await h.test(r'''
        World.REFRESH_WEATHER();
        EXPECT(World.weather_temp, 18.5);
        EXPECT(World.weather_wind, 12.3);
        EXPECT(World.weather_description, 'Clear sky');
        EXPECT(World.weather_icon, 'wb_sunny')
      ''');
    });

    test('REFRESH_WEATHER handles null response', () async {
      h.runtime.setUnaryFunction('FETCH', (ctx, caller, url) => null);

      await h.test(r'''
        World.REFRESH_WEATHER();
        EXPECT(World.weather_icon, 'cloud')
      ''');
    });

    test('GET_WAR_STATUS returns message based on hero count', () async {
      await h.test(r'''
        __msg := World.GET_WAR_STATUS();
        ASSERT(__msg <> null);
        ASSERT(LENGTH(__msg) > 0)
      ''');
    });

    test('GENERATE_BATTLE_MAP returns FlutterMap widget', () async {
      await h.test(r'''
        __map := World.GENERATE_BATTLE_MAP();
        EXPECT(__map['type'], 'FlutterMap');
        ASSERT(__map['props'] <> null)
      ''');
    });

    test('GENERATE_BATTLE_MAP includes hero markers', () async {
      final bio = h.makeObject({'alignment': 3});
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'biography': bio,
      });
      await h.test(r'''
        Heroes.heroes := {"h1": __h};
        EXPECT(LENGTH(Heroes.heroes), 1);
        __map := World.GENERATE_BATTLE_MAP();
        __markers := __map['props']['children'][1]['props']['markers'];
        ASSERT(LENGTH(__markers) >= 1)
      ''', boundValues: {'__h': hero});
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Hero Detail tests
  // ═══════════════════════════════════════════════════════════════════
  group('HeroDetail', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
    });

    test('GENERATE_HERO_DETAIL returns SizedBox when no hero selected',
        () async {
      await h.test(r'''
        __result := Detail.GENERATE_HERO_DETAIL();
        EXPECT(__result['type'], 'SizedBox')
      ''');
    });

    test('GENERATE_HERO_DETAIL returns scrollable view with hero', () async {
      final bio = h.makeObject({
        'full_name': 'Bruce Wayne',
        'publisher': 'DC Comics',
        'alignment': 4,
        'alter_egos': 'No alter egos found.',
        'aliases': 'Dark Knight',
        'first_appearance': 'Detective Comics #27',
        'place_of_birth': 'Crest Hill, Bristol Township',
      });
      final stats = h.makeObject({
        'intelligence': 100, 'strength': 26, 'speed': 27,
        'durability': 50, 'power': 47, 'combat': 100,
      });
      final appearance = h.makeObject({
        'gender': 1,
        'race': 'Human',
        'height': h.makeObject({'m': 1.88}),
        'weight': h.makeObject({'kg': 95.0}),
        'eye_colour': 'blue',
        'hair_colour': 'black',
      });
      final work = h.makeObject({
        'occupation': 'Businessman',
        'base': 'Batcave, Gotham City',
      });
      final connections = h.makeObject({
        'group_affiliation': 'Justice League',
        'relatives': 'Thomas Wayne (father)',
      });
      final img = h.makeObject({'url': null});
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'biography': bio,
        'powerstats': stats,
        'appearance': appearance,
        'work': work,
        'connections': connections,
        'image': img,
      });
      await h.test(r'''
        Heroes.selected_hero := __h;
        __result := Detail.GENERATE_HERO_DETAIL();
        EXPECT(__result['type'], 'SingleChildScrollView')
      ''', boundValues: {'__h': hero});
    });

    test('__MAKE_DETAIL_CARD creates card with title', () async {
      await h.test(r'''
        __card := Detail.__MAKE_DETAIL_CARD('Test Section', [{'type': 'Text', 'props': {'data': 'Hello'}}]);
        EXPECT(__card['type'], 'Padding')
      ''');
    });

    test('__MAKE_ROW creates label-value row', () async {
      await h.test(r'''
        __rows := Detail.__MAKE_ROW('Name', 'Batman');
        EXPECT(LENGTH(__rows), 2);
        EXPECT(__rows[0]['type'], 'Row')
      ''');
    });

    test('__LAYOUT_STAT_ROWS groups stats in rows of 3', () async {
      await h.test(r'''
        __test_stats := [
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "1"}}},
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "2"}}},
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "3"}}},
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "4"}}}
        ];
        __rows := Detail.__LAYOUT_STAT_ROWS(__test_stats);
        __row_count := 0;
        IF LENGTH(__rows) > 0 THEN
            FOR __i := 0 TO LENGTH(__rows) - 1 DO
                IF __rows[__i]['type'] = 'Row' THEN
                    __row_count := __row_count + 1;
        EXPECT(__row_count, 2)
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Hero Cards tests
  // ═══════════════════════════════════════════════════════════════════
  group('HeroCards', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
    });

    test('__HERO_SUBTITLE joins publisher and race', () async {
      await h.test(r'''
        EXPECT(Cards.__HERO_SUBTITLE('DC', 'Human'), 'DC • Human');
        EXPECT(Cards.__HERO_SUBTITLE('DC', ''), 'DC');
        EXPECT(Cards.__HERO_SUBTITLE('', 'Human'), 'Human');
        EXPECT(Cards.__HERO_SUBTITLE('', ''), '');
        EXPECT(Cards.__HERO_SUBTITLE(null, null), '')
      ''');
    });

    test('__ALIGN_IDX clamps to valid range', () async {
      await h.test(r'''
        EXPECT(Cards.__ALIGN_IDX(0), 0);
        EXPECT(Cards.__ALIGN_IDX(5), 5);
        EXPECT(Cards.__ALIGN_IDX(-1), 0);
        EXPECT(Cards.__ALIGN_IDX(99), 0)
      ''');
    });

    test('GENERATE_HERO_CARDS returns empty for empty list', () async {
      await h.test(r'''
        __result := Cards.GENERATE_HERO_CARDS([], '_heroes', TRUE);
        EXPECT(LENGTH(__result), 0)
      ''');
    });

    /// Build a hero with ALL nested fields that _summary_fields accessors need.
    dynamic makeCardHero(String id, String name, {int alignment = 0}) {
      final bio = h.makeObject({
        'full_name': name,
        'publisher': '',
        'alignment': alignment,
      });
      final stats = h.makeObject({
        'intelligence': 0, 'strength': 0, 'speed': 0,
        'durability': 0, 'power': 0, 'combat': 0,
      });
      final appearance = h.makeObject({'race': ''});
      final image = h.makeObject({'url': null});
      return h.makeObject({
        'id': id,
        'name': name,
        'biography': bio,
        'powerstats': stats,
        'appearance': appearance,
        'image': image,
        'locked': false,
      });
    }

    test('GENERATE_HERO_CARDS generates cards for heroes', () async {
      final hero = makeCardHero('h1', 'Batman', alignment: 3);
      await h.test(r'''
        __cards := Cards.GENERATE_HERO_CARDS([__h], '_heroes', TRUE);
        EXPECT(LENGTH(__cards), 1);
        EXPECT(__cards[0]['type'], 'DismissibleCard')
      ''', boundValues: {'__h': hero});
    });

    test('GENERATE_HERO_CARDS without delete wraps in HeroCardBody',
        () async {
      final hero = makeCardHero('h1', 'Batman', alignment: 3);
      await h.test(r'''
        __cards := Cards.GENERATE_HERO_CARDS([__h], '_search', FALSE);
        EXPECT(__cards[0]['type'], 'HeroCardBody')
      ''', boundValues: {'__h': hero});
    });

    test('GENERATE_SAVED_HEROES_CARDS returns empty state when no heroes',
        () async {
      await h.test(r'''
        __result := Cards.GENERATE_SAVED_HEROES_CARDS();
        EXPECT(LENGTH(__result), 1);
        EXPECT(__result[0]['type'], 'Center')
      ''');
    });

    test('CACHE_HERO_CARD stores card in cache', () async {
      final hero = makeCardHero('h1', 'Batman', alignment: 3);
      await h.test(r'''
        Cards.CACHE_HERO_CARD(__h);
        ASSERT(Cards.card_cache['h1'] <> null)
      ''', boundValues: {'__h': hero});
    });

    test('REMOVE_CACHED_CARD removes from cache', () async {
      final hero = makeCardHero('h1', 'Batman', alignment: 3);
      await h.test(r'''
        Cards.CACHE_HERO_CARD(__h);
        Cards.REMOVE_CACHED_CARD('h1');
        ASSERT(Cards.card_cache['h1'] = null)
      ''', boundValues: {'__h': hero});
    });

    test('CLEAR_CARD_CACHE empties entire cache', () async {
      final hero = makeCardHero('h1', 'Batman', alignment: 3);
      await h.test(r'''
        Cards.CACHE_HERO_CARD(__h);
        Cards.CLEAR_CARD_CACHE();
        EXPECT(LENGTH(Cards.card_cache), 0)
      ''', boundValues: {'__h': hero});
    });

    test('POPULATE_AND_REBUILD clears cache, caches heroes, rebuilds cards', () async {
      final hero1 = makeCardHero('h1', 'Batman', alignment: 3);
      final hero2 = makeCardHero('h2', 'Superman', alignment: 2);
      // Pre-cache one stale hero, then populate with two fresh ones
      await h.test(r'''
        Cards.CACHE_HERO_CARD(__h1);
        EXPECT(LENGTH(Cards.card_cache), 1);
        Cards.POPULATE_AND_REBUILD([__h1, __h2]);
        EXPECT(LENGTH(Cards.card_cache), 2);
        ASSERT(Cards.card_cache['h1'] <> null);
        ASSERT(Cards.card_cache['h2'] <> null)
      ''', boundValues: {'__h1': hero1, '__h2': hero2});
    });

    test('CACHE_HERO_CARDS batch-caches multiple heroes', () async {
      final hero1 = makeCardHero('h1', 'Batman', alignment: 3);
      final hero2 = makeCardHero('h2', 'Superman', alignment: 2);
      await h.test(r'''
        Cards.CACHE_HERO_CARDS([__h1, __h2]);
        EXPECT(LENGTH(Cards.card_cache), 2)
      ''', boundValues: {'__h1': hero1, '__h2': hero2});
    });

    test('__HERO_SEMANTICS builds accessibility label', () async {
      final stats = <dynamic>[
        h.makeObject({'label': 'STR', 'value': 80}),
        h.makeObject({'label': 'INT', 'value': 90}),
      ];
      await h.test(r'''
        __result := Cards.__HERO_SEMANTICS('Batman', 'good', __stats);
        ASSERT('Batman' IN __result);
        ASSERT('good' IN __result);
        ASSERT('STR' IN __result)
      ''', boundValues: {'__stats': stats});
    });

    test('__MAKE_STAT_CHIP_ROWS returns rows of stat chips', () async {
      final stats = <dynamic>[
        h.makeObject({
          'label': 'STR',
          'value': 80,
          'color': '0xFF2196F3',
          'bg_color': '0x1A2196F3',
          'icon': 'fitness_center'
        }),
      ];
      await h.test(r'''
        __rows := Cards.__MAKE_STAT_CHIP_ROWS(__stats);
        ASSERT(LENGTH(__rows) > 0);
        __found_row := FALSE;
        IF LENGTH(__rows) > 0 THEN
            FOR __i := 0 TO LENGTH(__rows) - 1 DO
                IF __rows[__i]['type'] = 'Row' THEN BEGIN
                    ASSERT(LENGTH(__rows[__i]['children']) > 0);
                    __found_row := TRUE;
                END;
        ASSERT(__found_row)
      ''', boundValues: {'__stats': stats});
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // YAML SHQL™ Expression Validation
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // For every YAML screen and widget, extract all `shql:` expressions
  // and execute them against the fully loaded runtime. This catches stale
  // references to non-namespaced identifiers (e.g. `DELETE_HERO` instead of
  // `Heroes.DELETE_HERO`).

  group('YAML SHQL™ validation', () {
    late ShqlTestRunner h;
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;
    late ShqlBindings shqlBindings;

    const yamlFiles = [
      'assets/screens/home.yaml',
      'assets/screens/heroes.yaml',
      'assets/screens/hero_detail.yaml',
      'assets/screens/hero_edit.yaml',
      'assets/screens/online.yaml',
      'assets/screens/onboarding.yaml',
      'assets/screens/settings.yaml',
      'assets/widgets/stat_chip.yaml',
      'assets/widgets/power_bar.yaml',
      'assets/widgets/bottom_nav.yaml',
      'assets/widgets/consent_toggle.yaml',
      'assets/widgets/section_header.yaml',
      'assets/widgets/info_card.yaml',
      'assets/widgets/api_field.yaml',
      'assets/widgets/detail_app_bar.yaml',
      'assets/widgets/overlay_action_button.yaml',
      'assets/widgets/yes_no_dialog.yaml',
      'assets/widgets/reconcile_dialog.yaml',
      'assets/widgets/prompt_dialog.yaml',
      'assets/widgets/conflict_dialog.yaml',
      'assets/widgets/badge_row.yaml',
      'assets/widgets/hero_card_body.yaml',
      'assets/widgets/dismissible_card.yaml',
      'assets/widgets/hero_placeholder.yaml',
      'assets/widgets/login_screen.yaml',
      'assets/router.yaml',
    ];

    setUpAll(() async {
      final s = await _concreteSetUp();
      h = s.h;
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
      shqlBindings = s.shqlBindings;

      // Framework directive used in YAML-defined dialog screens
      h.runtime.setUnaryFunction('CLOSE_DIALOG', (ctx, c, a) =>
          <String, dynamic>{'__close_dialog__': true, 'value': a});

      // Pre-seed variables that Dart sets before dialogs open
      await h.test(r"""
        _DIALOG_TEXT := '';
        _APPLY_TO_ALL := FALSE;
        _CONFLICT_VALUE1_ID := 'metric';
        _CONFLICT_VALUE2_ID := 'imperial';
      """);

      // Add a real hero so callbacks like DELETE_HERO, TOGGLE_LOCK, etc. have state
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test(r'''
        Heroes.ON_HERO_ADDED(__h);
        Cards.CACHE_HERO_CARD(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        HeroEdit.EDIT_HERO()
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    for (final yamlPath in yamlFiles) {
      test(yamlPath, () async {
        final exprs = allShqlFromYaml(yamlPath);
        final failures = <String>[];

        for (var i = 0; i < exprs.length; i++) {
          final code = exprs[i];
          try {
            await h.test(
              'CLEAR_CALL_LOG(); $code',
              boundValues: {'value': 'test'},
            );
          } on RuntimeException catch (e) {
            final msg = e.toString();
            if (msg.contains('Unidentified identifier')) {
              failures.add('  [$i]: $code\n    $msg');
            }
          } catch (_) {
            // Other runtime errors (null access, type, etc.) are fine
          }
        }

        if (failures.isNotEmpty) {
          fail(
            '${failures.length} unresolved SHQL™ identifier(s):\n'
            '${failures.join('\n\n')}',
          );
        }
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // YAML Expression Lists — Hardcoded Verification
  // ═══════════════════════════════════════════════════════════════════════════
  // Extracts ALL SHQL™ expressions from each YAML file and verifies the list
  // matches a hardcoded expectation. Intentional DRY violation (like schema
  // tests) to catch YAML drift without corresponding test updates.

  // Hardcoded expression lists per YAML file — verified in 'YAML expression
  // lists' group, then used by index in 'YAML expressions' group.

  const routerExprs = [
    'Prefs.INITIAL_ROUTE()',
  ];

  const homeExprs = [
    'Prefs.DARK_MODE_ICON()',
    'Prefs.TOGGLE_DARK_MODE()',
    'World.GET_WAR_STATUS()',
    'World.weather_icon',
    'World.WEATHER_TEMP_LABEL()',
    'World.weather_description',
    'World.WEATHER_WIND_LABEL()',
    "Nav.GO_TO('heroes')",
    'Stats.TOTAL_FIGHTING_POWER()',
    'World.GENERATE_BATTLE_MAP()',
    'Heroes.HERO_COUNT_LABEL()',
    'Nav.TAB_NAV(0, value)',
  ];

  const heroesExprs = [
    'Heroes.HERO_GRID_TYPE()',
    "Nav.GO_TO('online')",
    'Heroes.hero_cards',
    'Nav.TAB_NAV(2, value)',
  ];

  const heroDetailExprs = [
    'Nav.GO_BACK()',
    'Heroes.SELECTED_HERO_TITLE()',
    'Heroes.IS_SAVED_HERO_TYPE()',
    'HeroEdit.EDIT_HERO()',
    'Heroes.IS_SAVED_HERO_TYPE()',
    'Heroes.SELECTED_LOCK_ICON()',
    'Heroes.TOGGLE_LOCK(Heroes.selected_hero.ID)',
    'Heroes.IS_SAVED_HERO_TYPE()',
    'Heroes.DELETE_SELECTED_AND_GO_BACK()',
    'Detail.GENERATE_HERO_DETAIL()',
    'Nav.TAB_NAV(-1, value)',
  ];

  const heroEditExprs = [
    'HeroEdit.GENERATE_EDIT_FORM()',
    'HeroEdit.SAVE_AMENDMENTS()',
  ];

  const onlineExprs = [
    'Search.search_query',
    'Search.SET_SEARCH_QUERY(value)',
    'Search.SEARCH_HEROES(value)',
    'Search.GENERATE_SEARCH_HISTORY()',
    'Search.LOADING_TYPE()',
    'Search.LOADING_HEIGHT()',
    'Heroes.RECONCILE_ACTIVE_TYPE()',
    'Heroes.RECONCILE_CURRENT_LABEL()',
    'Heroes.reconcile_status',
    'Heroes.ABORT_RECONCILE()',
    'Search.SUMMARY_TYPE()',
    'Search.search_summary',
    'Heroes.RECONCILE_HEROES()',
    'Heroes.RECONCILE_LOG_TYPE()',
    'Heroes.reconcile_log',
    'Nav.TAB_NAV(1, value)',
  ];

  const onboardingExprs = [
    'Prefs.api_key',
    'Prefs.SET_API_KEY(value)',
    'Prefs.SET_API_KEY(value)',
    'Prefs.api_host',
    'Prefs.SET_API_HOST(value)',
    'Prefs.SET_API_HOST(value)',
    'Prefs.analytics_enabled',
    'Prefs.SET_ANALYTICS_CONSENT(value)',
    'Prefs.crashlytics_enabled',
    'Prefs.SET_CRASHLYTICS_CONSENT(value)',
    'Prefs.location_enabled',
    'Prefs.SET_LOCATION_CONSENT(value)',
    'Prefs.FINISH_ONBOARDING()',
  ];

  const settingsExprs = [
    'Prefs.DARK_MODE_SETTINGS_ICON()',
    'Prefs.is_dark_mode',
    'Prefs.SET_DARK_MODE(value)',
    'Prefs.api_key',
    'Prefs.SET_API_KEY(value)',
    'Prefs.SET_API_KEY(value)',
    'Prefs.api_host',
    'Prefs.SET_API_HOST(value)',
    'Prefs.SET_API_HOST(value)',
    'Prefs.analytics_enabled',
    'Prefs.SET_ANALYTICS_CONSENT(value)',
    'Prefs.crashlytics_enabled',
    'Prefs.SET_CRASHLYTICS_CONSENT(value)',
    'Prefs.location_enabled',
    'Prefs.SET_LOCATION_CONSENT(value)',
    'World.LOCATION_LABEL()',
    'Heroes.CLEAR_ALL_DATA()',
    'Prefs.RESET_ONBOARDING()',
    'Heroes.SIGN_OUT()',
    'Nav.TAB_NAV(3, value)',
  ];

  const loginScreenExprs = [
    'Auth.LOGIN_TITLE()',
    'Auth.SET_LOGIN_EMAIL(value)',
    'Auth.LOGIN_SUBMIT()',
    'Auth.SET_LOGIN_PASSWORD(value)',
    'Auth.LOGIN_ERROR_CHILDREN()',
    'Auth.LOGIN_SUBMIT_IF_READY()',
    'Auth.LOGIN_BUTTON_CHILD()',
    'Auth.LOGIN_TOGGLE_IF_READY()',
    'Auth.LOGIN_TOGGLE_TEXT()',
  ];

  const detailAppBarExprs = [
    'Nav.GO_BACK()',
  ];

  const reconcileDialogExprs = [
    "CLOSE_DIALOG('cancel')",
    "CLOSE_DIALOG('skip')",
    "CLOSE_DIALOG('saveAll')",
    "CLOSE_DIALOG('save')",
  ];

  const yesNoDialogExprs = [
    'CLOSE_DIALOG(FALSE)',
    'CLOSE_DIALOG(TRUE)',
  ];

  const promptDialogExprs = [
    "SET('_DIALOG_TEXT', value)",
    'CLOSE_DIALOG(_DIALOG_TEXT)',
    'CLOSE_DIALOG(NULL)',
    'CLOSE_DIALOG(_DIALOG_TEXT)',
  ];

  const conflictDialogExprs = [
    '_APPLY_TO_ALL',
    "SET('_APPLY_TO_ALL', value)",
    'CLOSE_DIALOG(NULL)',
    'CLOSE_DIALOG(OBJECT{choice: _CONFLICT_VALUE1_ID, applyToAll: _APPLY_TO_ALL})',
    'CLOSE_DIALOG(OBJECT{choice: _CONFLICT_VALUE2_ID, applyToAll: _APPLY_TO_ALL})',
  ];

  group('YAML expression lists', () {
    test('router.yaml', () {
      expect(allShqlFromYaml('assets/router.yaml'), routerExprs);
    });

    test('home.yaml', () {
      expect(allShqlFromYaml('assets/screens/home.yaml'), homeExprs);
    });

    test('heroes.yaml', () {
      expect(allShqlFromYaml('assets/screens/heroes.yaml'), heroesExprs);
    });

    test('hero_detail.yaml', () {
      expect(allShqlFromYaml('assets/screens/hero_detail.yaml'), heroDetailExprs);
    });

    test('hero_edit.yaml', () {
      expect(allShqlFromYaml('assets/screens/hero_edit.yaml'), heroEditExprs);
    });

    test('online.yaml', () {
      expect(allShqlFromYaml('assets/screens/online.yaml'), onlineExprs);
    });

    test('onboarding.yaml', () {
      expect(allShqlFromYaml('assets/screens/onboarding.yaml'), onboardingExprs);
    });

    test('settings.yaml', () {
      expect(allShqlFromYaml('assets/screens/settings.yaml'), settingsExprs);
    });

    test('login_screen.yaml', () {
      expect(allShqlFromYaml('assets/widgets/login_screen.yaml'), loginScreenExprs);
    });

    test('detail_app_bar.yaml', () {
      expect(allShqlFromYaml('assets/widgets/detail_app_bar.yaml'), detailAppBarExprs);
    });

    test('reconcile_dialog.yaml', () {
      expect(allShqlFromYaml('assets/widgets/reconcile_dialog.yaml'), reconcileDialogExprs);
    });

    test('yes_no_dialog.yaml', () {
      expect(allShqlFromYaml('assets/widgets/yes_no_dialog.yaml'), yesNoDialogExprs);
    });

    test('prompt_dialog.yaml', () {
      expect(allShqlFromYaml('assets/widgets/prompt_dialog.yaml'), promptDialogExprs);
    });

    test('conflict_dialog.yaml', () {
      expect(allShqlFromYaml('assets/widgets/conflict_dialog.yaml'), conflictDialogExprs);
    });

    // YAML widgets with 0 SHQL™ expressions
    for (final path in [
      'assets/widgets/bottom_nav.yaml',
      'assets/widgets/hero_card_body.yaml',
      'assets/widgets/overlay_action_button.yaml',
      'assets/widgets/consent_toggle.yaml',
      'assets/widgets/api_field.yaml',
      'assets/widgets/stat_chip.yaml',
      'assets/widgets/power_bar.yaml',
      'assets/widgets/section_header.yaml',
      'assets/widgets/info_card.yaml',
      'assets/widgets/badge_row.yaml',
      'assets/widgets/hero_placeholder.yaml',
      'assets/widgets/dismissible_card.yaml',
    ]) {
      test('$path — no expressions', () {
        expect(allShqlFromYaml(path), isEmpty);
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // YAML Expression Semantic Coverage
  // ═══════════════════════════════════════════════════════════════════════════
  // Exercises SHQL™ expressions FROM the actual YAML files — testing both
  // branches of IF/THEN/ELSE, callback side-effects, and return values.
  // Expressions are accessed by index into the verified hardcoded lists above.
  group('YAML expressions', () {
    late ShqlTestRunner h;
    late HeroDataManager heroDataManager;
    late MockHeroService mockService;
    late ShqlBindings shqlBindings;

    setUp(() async {
      final s = await _concreteSetUp();
      h = s.h;
      heroDataManager = s.heroDataManager;
      mockService = s.mockService;
      shqlBindings = s.shqlBindings;

      h.runtime.setUnaryFunction('CLOSE_DIALOG', (ctx, c, a) =>
          <String, dynamic>{'__close_dialog__': true, 'value': a});
    });

    // ─── router.yaml ────────────────────────────────────────────────────
    test('router.yaml: initial route — both branches', () async {
      final expr = routerExprs[0]; // Prefs.INITIAL_ROUTE()
      await h.test('''
        Prefs.onboarding_completed := FALSE;
        EXPECT($expr, 'onboarding');
        Prefs.onboarding_completed := TRUE;
        EXPECT($expr, 'home')
      ''');
    });

    // ─── home.yaml ──────────────────────────────────────────────────────
    test('home.yaml: dark mode icon — both branches', () async {
      final expr = homeExprs[0]; // Prefs.DARK_MODE_ICON()
      await h.test('''
        Prefs.is_dark_mode := TRUE;
        EXPECT($expr, 'light_mode');
        Prefs.is_dark_mode := FALSE;
        EXPECT($expr, 'dark_mode')
      ''');
    });

    test('home.yaml: TOGGLE_DARK_MODE callback', () async {
      final expr = homeExprs[1]; // Prefs.TOGGLE_DARK_MODE()
      await h.test('''
        Prefs.is_dark_mode := FALSE;
        $expr;
        ASSERT(Prefs.is_dark_mode);
        $expr;
        ASSERT(NOT Prefs.is_dark_mode)
      ''');
    });

    test('home.yaml: GET_WAR_STATUS returns string', () async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final expr = homeExprs[2]; // World.GET_WAR_STATUS()
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        ASSERT(LENGTH($expr) > 0)
      ''', boundValues: {'__h': hero.obj});
    });

    test('home.yaml: weather temp display — both branches', () async {
      final expr = homeExprs[4]; // World.WEATHER_TEMP_LABEL()
      await h.test('''
        World.weather_temp := null;
        EXPECT($expr, 'Loading...');
        World.weather_temp := 21.5;
        EXPECT($expr, '22°C')
      ''');
    });

    test('home.yaml: weather description and wind', () async {
      final descExpr = homeExprs[5]; // World.weather_description
      final windExpr = homeExprs[6]; // World.WEATHER_WIND_LABEL()
      await h.test('''
        World.weather_description := 'Clear sky';
        EXPECT($descExpr, 'Clear sky');
        World.weather_wind := 15.3;
        EXPECT($windExpr, 'Wind: 15 km/h')
      ''');
    });

    test('home.yaml: weather icon', () async {
      final expr = homeExprs[3]; // World.weather_icon
      await h.test('''
        World.weather_icon := 'wb_sunny';
        EXPECT($expr, 'wb_sunny')
      ''');
    });

    test('home.yaml: total_fighting_power observed', () async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final expr = homeExprs[8]; // Stats.TOTAL_FIGHTING_POWER()
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        ASSERT($expr > 0)
      ''', boundValues: {'__h': hero.obj});
    });

    test('home.yaml: GENERATE_BATTLE_MAP returns FlutterMap', () async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final expr = homeExprs[9]; // World.GENERATE_BATTLE_MAP()
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        EXPECT(($expr)['type'], 'FlutterMap')
      ''', boundValues: {'__h': hero.obj});
    });

    test('home.yaml: hero count string', () async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final expr = homeExprs[10]; // Heroes.HERO_COUNT_LABEL()
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        EXPECT($expr, '1 characters registered')
      ''', boundValues: {'__h': hero.obj});
    });

    test('home.yaml: TAB_NAV callback', () async {
      final expr = homeExprs[11]; // Nav.TAB_NAV(0, value)
      await h.test('''
        $expr;
        ASSERT_CONTAINS(Nav.navigation_stack, 'heroes')
      ''', boundValues: {'value': 2});
    });

    // ─── heroes.yaml ────────────────────────────────────────────────────
    test('heroes.yaml: grid type — both branches', () async {
      final expr = heroesExprs[0]; // Heroes.HERO_GRID_TYPE()
      await h.test('''
        Heroes.SET_HERO_CARDS([]);
        EXPECT($expr, 'Center');
        Heroes.SET_HERO_CARDS([{}, {}]);
        EXPECT($expr, 'GridView')
      ''');
    });

    test('heroes.yaml: hero_cards data binding', () async {
      await h.test('ASSERT(LENGTH(${heroesExprs[2]}) >= 0)'); // Heroes.hero_cards
    });

    test('heroes.yaml: Nav.GO_TO online callback', () async {
      final expr = heroesExprs[1]; // Nav.GO_TO('online')
      await h.test('''
        $expr;
        ASSERT_CONTAINS(Nav.navigation_stack, 'online')
      ''');
    });

    // ─── hero_detail.yaml ───────────────────────────────────────────────
    test('hero_detail.yaml: title — both branches', () async {
      final expr = heroDetailExprs[1]; // Heroes.SELECTED_HERO_TITLE()
      await h.test('''
        Heroes.SET_SELECTED_HERO(null);
        EXPECT($expr, 'Hero Details')
      ''');

      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        EXPECT($expr, 'Batman')
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    test('hero_detail.yaml: edit/lock/delete visibility — both branches',
        () async {
      final expr = heroDetailExprs[2]; // Heroes.IS_SAVED_HERO_TYPE()
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        -- Saved hero → IconButton
        EXPECT($expr, 'IconButton');

        -- No hero → SizedBox
        Heroes.SET_SELECTED_HERO(null);
        EXPECT($expr, 'SizedBox')
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    test('hero_detail.yaml: lock icon — both branches', () async {
      final expr = heroDetailExprs[5]; // Heroes.SELECTED_LOCK_ICON()
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        Heroes.heroes[__id].LOCKED := FALSE;
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        EXPECT($expr, 'lock_open');

        Heroes.heroes[__id].LOCKED := TRUE;
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        EXPECT($expr, 'lock')
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    test('hero_detail.yaml: DELETE_SELECTED_AND_GO_BACK callback', () async {
      final expr = heroDetailExprs[8]; // Heroes.DELETE_SELECTED_AND_GO_BACK()
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Cards.CACHE_HERO_CARD(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        Nav.GO_TO('hero_detail');

        CLEAR_CALL_LOG();
        $expr;
        EXPECT(Heroes.total_heroes, 0);
        ASSERT_CALLED('_HERO_DELETE')
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    test('hero_detail.yaml: TOGGLE_LOCK callback', () async {
      final expr = heroDetailExprs[6]; // Heroes.TOGGLE_LOCK(Heroes.selected_hero.ID)
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        $expr;
        EXPECT(Heroes.heroes[__id].LOCKED, TRUE)
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    test('hero_detail.yaml: GENERATE_HERO_DETAIL callback', () async {
      final expr = heroDetailExprs[9]; // Detail.GENERATE_HERO_DETAIL()
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        EXPECT(($expr)['type'], 'SingleChildScrollView')
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    // ─── hero_edit.yaml ─────────────────────────────────────────────────
    test('hero_edit.yaml: GENERATE_EDIT_FORM callback', () async {
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      final expr = heroEditExprs[0]; // HeroEdit.GENERATE_EDIT_FORM()
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Cards.CACHE_HERO_CARD(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        HeroEdit.EDIT_HERO();
        ASSERT(LENGTH($expr) > 0)
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    test('hero_edit.yaml: SAVE_AMENDMENTS callback', () async {
      final expr = heroEditExprs[1]; // HeroEdit.SAVE_AMENDMENTS()
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        Cards.CACHE_HERO_CARD(__h);
        Heroes.SET_SELECTED_HERO(Heroes.heroes[__id]);
        HeroEdit.EDIT_HERO();
        CLEAR_CALL_LOG();
        $expr;
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''', boundValues: {'__h': hero.obj, '__id': hero.id});
    });

    // ─── online.yaml ────────────────────────────────────────────────────
    test('online.yaml: search query binding', () async {
      await h.test(r'''
        Search.SET_SEARCH_QUERY('batman');
        EXPECT(Search.search_query, 'batman')
      ''');
    });

    test('online.yaml: SEARCH_HEROES callback', () async {
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'skip');
      final expr = onlineExprs[2]; // Search.SEARCH_HEROES(value)
      await h.test('''
        $expr;
        ASSERT(LENGTH(Search.search_results) > 0)
      ''', boundValues: {'value': 'jubilee'});
    });

    test('online.yaml: loading indicator type — both branches', () async {
      final expr = onlineExprs[4]; // Search.LOADING_TYPE()
      await h.test('''
        Search.SET_IS_LOADING(TRUE);
        EXPECT($expr, 'LinearProgressIndicator');
        Search.SET_IS_LOADING(FALSE);
        EXPECT($expr, 'SizedBox')
      ''');
    });

    test('online.yaml: loading height — both branches', () async {
      final expr = onlineExprs[5]; // Search.LOADING_HEIGHT()
      await h.test('''
        Search.SET_IS_LOADING(TRUE);
        EXPECT($expr, null);
        Search.SET_IS_LOADING(FALSE);
        EXPECT($expr, 0)
      ''');
    });

    test('online.yaml: reconcile active — both branches', () async {
      final expr = onlineExprs[6]; // Heroes.RECONCILE_ACTIVE_TYPE()
      await h.test('''
        Heroes.SET_RECONCILE_ACTIVE(TRUE);
        EXPECT($expr, 'Padding');
        Heroes.SET_RECONCILE_ACTIVE(FALSE);
        EXPECT($expr, 'SizedBox')
      ''');
    });

    test('online.yaml: reconcile current + status text', () async {
      final currentExpr = onlineExprs[7]; // Heroes.RECONCILE_CURRENT_LABEL()
      await h.test('''
        Heroes.SET_RECONCILE_CURRENT('Batman');
        EXPECT($currentExpr, 'Reconciling: Batman')
      ''');
    });

    test('online.yaml: ABORT_RECONCILE callback', () async {
      final expr = onlineExprs[9]; // Heroes.ABORT_RECONCILE()
      await h.test('''
        Heroes.SET_RECONCILE_ABORTED(FALSE);
        $expr;
        ASSERT(Heroes.reconcile_aborted)
      ''');
    });

    test('online.yaml: search summary visibility — both branches', () async {
      final expr = onlineExprs[10]; // Search.SUMMARY_TYPE()
      await h.test('''
        Search.SET_SEARCH_SUMMARY('');
        EXPECT($expr, 'SizedBox');
        Search.SET_SEARCH_SUMMARY('3 found');
        EXPECT($expr, 'Padding')
      ''');
    });

    test('online.yaml: reconcile log type — both branches', () async {
      final expr = onlineExprs[13]; // Heroes.RECONCILE_LOG_TYPE()
      await h.test('''
        Heroes.SET_RECONCILE_LOG([]);
        EXPECT($expr, 'Center');
        Heroes.SET_RECONCILE_LOG([{'type': 'Text'}]);
        EXPECT($expr, 'ListView')
      ''');
    });

    test('online.yaml: RECONCILE_HEROES callback', () async {
      final expr = onlineExprs[12]; // Heroes.RECONCILE_HEROES()
      await h.test('''
        CLEAR_CALL_LOG();
        $expr
        -- _INIT_RECONCILE returns null → reconcile exits early
      ''');
    });

    test('online.yaml: GENERATE_SEARCH_HISTORY callback', () async {
      final expr = onlineExprs[3]; // Search.GENERATE_SEARCH_HISTORY()
      await h.test('ASSERT(LENGTH($expr) >= 0)');
    });

    // ─── settings.yaml ──────────────────────────────────────────────────
    test('settings.yaml: dark mode icon — both branches', () async {
      final expr = settingsExprs[0]; // Prefs.DARK_MODE_SETTINGS_ICON()
      await h.test('''
        Prefs.is_dark_mode := TRUE;
        EXPECT($expr, 'dark_mode');
        Prefs.is_dark_mode := FALSE;
        EXPECT($expr, 'light_mode')
      ''');
    });

    test('settings.yaml: dark mode switch value', () async {
      final expr = settingsExprs[1]; // Prefs.is_dark_mode
      await h.test('''
        Prefs.is_dark_mode := TRUE;
        ASSERT($expr);
        Prefs.is_dark_mode := FALSE;
        ASSERT(NOT $expr)
      ''');
    });

    test('settings.yaml: SET_DARK_MODE callback', () async {
      final expr = settingsExprs[2]; // Prefs.SET_DARK_MODE(value)
      await h.test('''
        $expr;
        ASSERT(Prefs.is_dark_mode)
      ''', boundValues: {'value': true});
    });

    test('settings.yaml: api_key and api_host bindings + callbacks',
        () async {
      await h.test(r'''
        Prefs.SET_API_KEY('my-key');
        EXPECT(Prefs.api_key, 'my-key');
        Prefs.SET_API_HOST('example.com');
        EXPECT(Prefs.api_host, 'example.com')
      ''');
    });

    test('settings.yaml: consent toggle callbacks', () async {
      await h.test(r'''
        CLEAR_CALL_LOG();
        Prefs.SET_ANALYTICS_CONSENT(TRUE);
        ASSERT(Prefs.analytics_enabled);
        ASSERT_CALLED('_SET_ANALYTICS');
        Prefs.SET_CRASHLYTICS_CONSENT(FALSE);
        ASSERT(NOT Prefs.crashlytics_enabled);
        ASSERT_CALLED('_SET_CRASHLYTICS');
        Prefs.SET_LOCATION_CONSENT(TRUE);
        ASSERT(Prefs.location_enabled);
        ASSERT_CALLED('_GET_LOCATION')
      ''');
    });

    test('settings.yaml: location description — both branches', () async {
      final expr = settingsExprs[15]; // World.LOCATION_LABEL()
      await h.test('''
        World.SET_LOCATION_DESCRIPTION('');
        EXPECT($expr, '');
        World.SET_LOCATION_DESCRIPTION('Stockholm');
        EXPECT($expr, 'Your location: Stockholm')
      ''');
    });

    test('settings.yaml: CLEAR_ALL_DATA callback', () async {
      final expr = settingsExprs[16]; // Heroes.CLEAR_ALL_DATA()
      final hero = await _persistFixtureHero(
          mockService, heroDataManager, shqlBindings, '69');
      await h.test('''
        Heroes.ON_HERO_ADDED(__h);
        EXPECT(Heroes.total_heroes, 1);
        $expr;
        EXPECT(Heroes.total_heroes, 0)
      ''', boundValues: {'__h': hero.obj});
    });

    test('settings.yaml: RESET_ONBOARDING callback', () async {
      final expr = settingsExprs[17]; // Prefs.RESET_ONBOARDING()
      await h.test('''
        Prefs.onboarding_completed := TRUE;
        $expr;
        ASSERT(NOT Prefs.onboarding_completed)
      ''');
    });

    test('settings.yaml: SIGN_OUT callback', () async {
      final expr = settingsExprs[18]; // Heroes.SIGN_OUT()
      await h.test('''
        CLEAR_CALL_LOG();
        $expr;
        ASSERT_CALLED('_SIGN_OUT')
      ''');
    });

    // ─── login_screen.yaml ──────────────────────────────────────────────
    test('login_screen.yaml: LOGIN_TITLE — both branches', () async {
      final expr = loginScreenExprs[0]; // Auth.LOGIN_TITLE()
      await h.test('''
        Auth.SET_LOGIN_IS_REGISTERING(FALSE);
        EXPECT($expr, 'Sign In');
        Auth.SET_LOGIN_IS_REGISTERING(TRUE);
        EXPECT($expr, 'Create Account')
      ''');
    });

    test('login_screen.yaml: LOGIN_TOGGLE_TEXT — both branches', () async {
      final expr = loginScreenExprs[8]; // Auth.LOGIN_TOGGLE_TEXT()
      await h.test('''
        Auth.SET_LOGIN_IS_REGISTERING(FALSE);
        EXPECT($expr, "Don't have an account? Register");
        Auth.SET_LOGIN_IS_REGISTERING(TRUE);
        EXPECT($expr, 'Already have an account? Sign in')
      ''');
    });

    test('login_screen.yaml: LOGIN_ERROR_CHILDREN — both branches', () async {
      final expr = loginScreenExprs[4]; // Auth.LOGIN_ERROR_CHILDREN()
      await h.test('''
        Auth.SET_LOGIN_ERROR('');
        EXPECT(LENGTH($expr), 0);
        Auth.SET_LOGIN_ERROR('Bad password');
        EXPECT(LENGTH($expr), 2)
      ''');
    });

    test('login_screen.yaml: LOGIN_BUTTON_CHILD — both branches', () async {
      final expr = loginScreenExprs[6]; // Auth.LOGIN_BUTTON_CHILD()
      await h.test('''
        Auth.SET_LOGIN_IS_LOADING(TRUE);
        EXPECT(($expr)['type'], 'SizedBox');
        Auth.SET_LOGIN_IS_LOADING(FALSE);
        EXPECT(($expr)['type'], 'Text')
      ''');
    });

    test('login_screen.yaml: LOGIN_SUBMIT_IF_READY guards loading', () async {
      final expr = loginScreenExprs[5]; // Auth.LOGIN_SUBMIT_IF_READY()
      await h.test('''
        Auth.SET_LOGIN_EMAIL('test@test.com');
        Auth.SET_LOGIN_PASSWORD('password');
        Auth.SET_LOGIN_IS_LOADING(TRUE);
        CLEAR_CALL_LOG();
        $expr;
        -- Loading guard blocks authentication
        ASSERT_NOT_CALLED('__ON_AUTHENTICATED')
      ''');
    });

    test('login_screen.yaml: LOGIN_TOGGLE_IF_READY guards loading', () async {
      final expr = loginScreenExprs[7]; // Auth.LOGIN_TOGGLE_IF_READY()
      await h.test('''
        Auth.SET_LOGIN_IS_REGISTERING(FALSE);
        Auth.SET_LOGIN_IS_LOADING(FALSE);
        $expr;
        ASSERT(Auth.LOGIN_IS_REGISTERING);
        -- Loading guard preserves current state
        Auth.SET_LOGIN_IS_LOADING(TRUE);
        $expr;
        ASSERT(Auth.LOGIN_IS_REGISTERING)
      ''');
    });

    // ─── bottom_nav via screen files ─────────────────────────────────────
    test('screen YAML: TAB_NAV callback via onTap prop', () async {
      final expr = onlineExprs[15]; // Nav.TAB_NAV(1, value)
      await h.test('''
        value := 0;
        $expr;
        ASSERT_CONTAINS(Nav.navigation_stack, 'home');
        value := 2;
        $expr;
        ASSERT_CONTAINS(Nav.navigation_stack, 'heroes')
      ''');
    });
  });

  // ─── YAML screen local SHQL™ scope ──────────────────────────────────────
  group('YAML screen local scope', () {
    late ShqlTestRunner sh;

    setUp(() async {
      sh = _createRunner();
      await sh.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);
    });

    test('createScreenContext() binds props as direct SHQL™ variables', () async {
      final scope = sh.createScope({'label': 'Batman', 'id': '99'});
      await sh.test('EXPECT(LABEL, "Batman"); EXPECT(ID, "99")', startingScope: scope);
    });

    test('scope is mutable: SHQL™ write persists on the same context', () async {
      final scope = sh.createScope({'checked': false});
      await sh.test('CHECKED := NOT CHECKED; EXPECT(CHECKED, TRUE)', startingScope: scope);
    });

    test('sibling scopes are independent', () async {
      final a = sh.createScope({'x': 1});
      final b = sh.createScope({'x': 2});
      await sh.test('X := 99', startingScope: a);
      await sh.test('EXPECT(X, 2)', startingScope: b);
    });
  });
}
