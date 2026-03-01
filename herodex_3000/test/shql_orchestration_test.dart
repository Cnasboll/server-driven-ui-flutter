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
  h.runtime.setNullaryFunction('_HERO_DATA_CLEAR', (ctx, c) => null);
  h.runtime.setNullaryFunction('_SIGN_OUT', (ctx, c) => null);
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
  h.runtime.setUnaryFunction('_HERO_DATA_TOGGLE_LOCK', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_RECONCILE_FETCH', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_RECONCILE_DELETE', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_HERO_DATA_DELETE', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_RECONCILE_PROMPT', (ctx, c, a) => null);
  h.runtime.setUnaryFunction('_SHOW_SNACKBAR', (ctx, c, a) => null);
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
  h.runtime.setBinaryFunction('_HERO_DATA_AMEND', (ctx, c, a, b) => null);
  h.runtime.setBinaryFunction('_ON_PREF_CHANGED', (ctx, c, a, b) => null);
  h.runtime.setBinaryFunction('POST', (ctx, c, a, b) =>
      <String, dynamic>{'status': 0});
  h.runtime.setBinaryFunction('FETCH_AUTH', (ctx, c, a, b) => null);

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
/// All SHQL modules are the real production files (no stubs).
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
  h.mockUnary('_HERO_DATA_DELETE', (heroId) {
    if (heroId is String) return coordinator.heroDataDelete(heroId);
    return null;
  });
  h.mockUnary('_HERO_DATA_TOGGLE_LOCK', (heroId) {
    if (heroId is String) return coordinator.heroDataToggleLock(heroId);
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
  h.mockUnary('_RECONCILE_DELETE', (heroId) {
    if (heroId is String) coordinator.reconcileDelete(heroId);
    return null;
  });
  h.mockUnary('_RECONCILE_FETCH', (heroId) async {
    if (heroId is String) return await coordinator.reconcileFetch(heroId);
    return null;
  });
  h.mockUnary('_RECONCILE_PROMPT', (text) async =>
      await coordinator.reconcilePrompt(text?.toString() ?? ''));
  h.mockBinary('_HERO_DATA_AMEND', (heroId, amendment) async {
    if (heroId is String && heroId.isNotEmpty) {
      return await coordinator.heroDataAmend(heroId, amendment);
    }
    return null;
  });
  h.mockBinary('MATCH', (heroObj, queryText) =>
      coordinator.matchHeroObject(heroObj, queryText as String));

  // Nullary callbacks (no mockNullary in ShqlTestRunner yet)
  h.runtime.setNullaryFunction('_HERO_DATA_CLEAR',
      (ctx, c) => coordinator.heroDataClear());
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

  // _ON_PREF_CHANGED / _PROMPT: no-ops already registered, override to track
  h.mockBinary('_ON_PREF_CHANGED');
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
  // Heroes — concrete HeroCoordinator + real SHQL modules
  // Each test = one user action → SHQL assertions → Dart DB assertions
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

    test('ON_HERO_ADDED updates heroes map, stats, filters, card cache',
        () async {
      final batman = await addHero('69');
      await h.test(r'''
        EXPECT(Heroes.total_heroes, 1);
        ASSERT(Heroes.heroes[__id] <> null);
        ASSERT(Stats.height_count > 0);
        ASSERT(Stats.total_fighting_power > 0);
        EXPECT(LENGTH(Filters.displayed_heroes), 1);
        ASSERT(Cards.card_cache[__id] <> null)
      ''', boundValues: {'__id': batman.id});
    });

    test('DELETE_HERO removes from SHQL state, stats, filters, card cache, and DB',
        () async {
      final batman = await addHero('69');
      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.DELETE_HERO(__id);
        EXPECT(Heroes.total_heroes, 0);
        ASSERT(Heroes.heroes[__id] = null);
        EXPECT(Stats.height_count, 0);
        EXPECT(Stats.total_fighting_power, 0);
        EXPECT(LENGTH(Filters.displayed_heroes), 0);
        ASSERT(Cards.card_cache[__id] = null);
        ASSERT_CALLED('_HERO_DATA_DELETE')
      ''', boundValues: {'__id': batman.id});
      expect(heroDataManager.getById(batman.id), isNull);
    });

    test('DELETE_HERO is a no-op for unknown hero', () async {
      await h.test(r'''
        Heroes.DELETE_HERO('nonexistent');
        EXPECT(Heroes.total_heroes, 0)
      ''');
    });

    test('TOGGLE_LOCK toggles in SHQL state and DB', () async {
      final batman = await addHero('69');
      await h.test(r'''
        CLEAR_CALL_LOG();
        Heroes.TOGGLE_LOCK(__id);
        EXPECT(Heroes.heroes[__id].LOCKED, TRUE);
        ASSERT_CALLED('_HERO_DATA_TOGGLE_LOCK')
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
        EXPECT(Stats.height_count, 0);
        EXPECT(Stats.total_fighting_power, 0)
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

    test('two heroes: stats accumulate, filters grow', () async {
      await addHero('69'); // Batman
      await addHero('644'); // Superman (has weight conflict — resolved by test)
      await h.test(r'''
        EXPECT(Heroes.total_heroes, 2);
        ASSERT(Stats.height_count >= 2);
        ASSERT(Stats.total_fighting_power > 0);
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
  });

  // ═══════════════════════════════════════════════════════════════════
  // Reconciliation — concrete HeroCoordinator + real SHQL modules
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
        EXPECT(Stats.height_count, 0)
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
        ASSERT_CALLED('_RECONCILE_DELETE');
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
      // Minimal setup — no SHQL files needed for pure Dart parsing
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

    setUp(() async {
      final s = await _concreteSetUp();
      h = s.h;
      heroDataManager = s.heroDataManager;
    });

    test('short query (< 2 chars) returns empty, no API call', () async {
      await h.test(r'''
        Search.SEARCH_HEROES('a');
        EXPECT(LENGTH(Search.search_results), 0);
        ASSERT_NOT_CALLED('_SEARCH_HEROES')
      ''');
    });

    test('search "jubilee" + save: 1 hero saved to DB and SHQL state',
        () async {
      // User types "jubilee", presses enter, review dialog returns "save"
      h.mockTernary('_REVIEW_HERO', (model, current, total) => 'save');

      await h.test(r'''
        Search.SEARCH_HEROES('jubilee');

        -- SHQL state
        EXPECT(Heroes.total_heroes, 1);
        EXPECT(LENGTH(Search.search_results), 1);
        ASSERT('1 found' IN Search.search_summary);
        ASSERT('1 saved' IN Search.search_summary);

        -- Stats updated
        ASSERT(Stats.height_count > 0);

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
        ASSERT(Stats.height_count >= 2);

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
        ASSERT(Stats.height_count >= 3);
        EXPECT(LENGTH(Filters.displayed_heroes), 3);
        ASSERT(LENGTH(Cards.card_cache) >= 3)
      ''');

      expect(heroDataManager.heroes, hasLength(3));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HeroEdit — concrete HeroCoordinator + real SHQL modules
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

    test('SAVE_AMENDMENTS with real name change updates SHQL state and DB',
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

        -- SHQL state updated
        ASSERT(Heroes.heroes[__id] <> null);
        EXPECT(Heroes.total_heroes, 1);
        ASSERT_CALLED('_HERO_DATA_AMEND');

        -- Card re-cached
        ASSERT(Cards.card_cache[__id] <> null);

        -- Navigated back
        ASSERT_CALLED('_SHOW_SNACKBAR')
      ''', boundValues: {'__id': heroId});

      // DB: hero was amended and locked
      final dbHero = heroDataManager.getById(heroId);
      expect(dbHero, isNotNull);
      expect(dbHero!.locked, true);
    });

    test('SAVE_AMENDMENTS with no changes shows snackbar, no DB write',
        () async {
      await addAndEditHero('69');

      await h.test(r'''
        CLEAR_CALL_LOG();
        HeroEdit.SAVE_AMENDMENTS();
        ASSERT_NOT_CALLED('_HERO_DATA_AMEND');
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
              HeroEdit.edit_fields[__i].VALUE := 'Batman (Changed)'
      ''');

      final amendment = await h.test('HeroEdit.BUILD_AMENDMENT()');
      expect(amendment, isNotNull);
      expect(amendment, isA<Map>());
      final map = amendment as Map;
      expect(map['name'], 'Batman (Changed)');
    });

    test('GENERATE_EDIT_FORM produces widget tree from real fields',
        () async {
      await addAndEditHero('69');

      final form = await h.test('HeroEdit.GENERATE_EDIT_FORM()');
      expect(form, isA<List>());
      expect((form as List).length, greaterThan(0));
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

      final result =
          await h.test("Auth.FIREBASE_SIGN_IN('a@b.com', 'pass123')");
      expect(result, isNull, reason: 'null = success');
      expect(savedState['_auth_id_token'], 'tok123');
      expect(savedState['_auth_email'], 'a@b.com');
      expect(savedState['_auth_uid'], 'uid1');
      expect(savedState['_auth_refresh_token'], 'ref1');
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

      final result =
          await h.test("Auth.FIREBASE_SIGN_IN('a@b.com', 'wrong')");
      expect(result, isA<String>());
      expect(result, contains('Invalid email'));
    });

    test('FIREBASE_SIGN_UP calls signUp endpoint', () async {
      String? calledUrl;
      h.runtime.setBinaryFunction('POST', (ctx, caller, url, body) {
        calledUrl = url as String;
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

      await h.test("Auth.FIREBASE_SIGN_UP('a@b.com', 'pass')");
      expect(calledUrl, contains('signUp'));
    });

    test('FIREBASE_SIGN_OUT clears saved state', () async {
      savedState['_auth_id_token'] = 'tok';
      savedState['_auth_email'] = 'a@b.com';
      savedState['_auth_uid'] = 'uid';
      savedState['_auth_refresh_token'] = 'ref';

      await h.test('Auth.FIREBASE_SIGN_OUT()');

      expect(savedState['_auth_id_token'], isNull);
      expect(savedState['_auth_email'], isNull);
      expect(savedState['_auth_uid'], isNull);
      expect(savedState['_auth_refresh_token'], isNull);
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

      await h.test("EXPECT(Auth.FIREBASE_REFRESH_TOKEN(), 'new_tok')");
      expect(savedState['_auth_id_token'], 'new_tok');
      expect(savedState['_auth_refresh_token'], 'new_ref');
    });

    test('LOGIN_SUBMIT rejects empty email', () async {
      await h.test(r'''
        Auth.LOGIN_EMAIL := '';
        Auth.LOGIN_PASSWORD := 'pass';
        Auth.LOGIN_SUBMIT();
        EXPECT(Auth.LOGIN_IS_LOADING, FALSE);
        ASSERT('email and password' IN Auth.LOGIN_ERROR)
      ''');
    });

    test('LOGIN_SUBMIT signs in and calls __ON_AUTHENTICATED on success',
        () async {
      var authenticated = false;
      h.runtime.setNullaryFunction('__ON_AUTHENTICATED', (ctx, caller) {
        authenticated = true;
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
        Auth.LOGIN_EMAIL := 'a@b.com';
        Auth.LOGIN_PASSWORD := 'pass123';
        Auth.LOGIN_SUBMIT()
      ''');

      expect(authenticated, true);
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
        Auth.LOGIN_EMAIL := 'a@b.com';
        Auth.LOGIN_PASSWORD := 'wrong';
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
      final r = await h.test('Cloud.__TO_VALUE(TRUE)');
      expect(r, isA<Map>());
      expect((r as Map)['booleanValue'], true);
    });

    test('__TO_VALUE converts strings', () async {
      final r = await h.test("Cloud.__TO_VALUE('hello')") as Map;
      expect(r['stringValue'], 'hello');
    });

    test('__FROM_VALUE converts boolean values', () async {
      await h.test("EXPECT(Cloud.__FROM_VALUE({'booleanValue': TRUE}), TRUE)");
    });

    test('__FROM_VALUE converts integer values', () async {
      final r =
          await h.test('Cloud.__FROM_VALUE({"integerValue": "42"})');
      expect(r, 42);
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
      var patchCalled = false;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, a, b, c) {
        patchCalled = true;
        return <String, dynamic>{'status': 200};
      });

      await h.test("Cloud.SAVE('is_dark_mode', TRUE)");
      expect(patchCalled, false);
    });

    test('SAVE skips when key not in SYNCED_KEYS', () async {
      await h.test("Cloud.SET_AUTH_UID('uid1')");
      savedState['_auth_id_token'] = 'tok';

      var patchCalled = false;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, a, b, c) {
        patchCalled = true;
        return <String, dynamic>{'status': 200};
      });

      await h.test("Cloud.SAVE('not_synced_key', 'value')");
      expect(patchCalled, false);
    });

    test('SAVE calls PATCH_AUTH with correct URL', () async {
      await h.test("Cloud.SET_AUTH_UID('uid1')");
      savedState['_auth_id_token'] = 'tok';

      String? calledUrl;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, url, body, token) {
        calledUrl = url as String;
        return <String, dynamic>{'status': 200};
      });

      await h.test("Cloud.SAVE('is_dark_mode', TRUE)");
      expect(calledUrl, contains('server-driven-ui-flutter'));
      expect(calledUrl, contains('uid1'));
      expect(calledUrl, contains('is_dark_mode'));
    });

    test('SAVE retries with refresh on 401', () async {
      await h.test("Cloud.SET_AUTH_UID('uid1')");
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

      await h.test("Cloud.SAVE('is_dark_mode', TRUE)");
      expect(callCount, 2, reason: 'Should retry after 401');
    });

    test('LOAD_ALL returns empty map when no uid', () async {
      final r = await h.test('Cloud.LOAD_ALL()');
      expect(r, isA<Map>());
      expect((r as Map).isEmpty, true);
    });

    test('LOAD_ALL parses Firestore fields', () async {
      await h.test("Cloud.SET_AUTH_UID('uid1')");
      savedState['_auth_id_token'] = 'tok';

      h.runtime.setBinaryFunction('FETCH_AUTH', (ctx, caller, url, token) {
        return <String, dynamic>{
          'fields': <String, dynamic>{
            'is_dark_mode': <String, dynamic>{'booleanValue': true},
            'api_key': <String, dynamic>{'stringValue': 'mykey'},
            'unknown_key': <String, dynamic>{'stringValue': 'ignored'},
          }
        };
      });

      final r = await h.test('Cloud.LOAD_ALL()') as Map;
      expect(r['is_dark_mode'], true);
      expect(r['api_key'], 'mykey');
      expect(r.containsKey('unknown_key'), false,
          reason: 'Only SYNCED_KEYS are returned');
    });

    test('SAVE_PREF saves locally and to cloud', () async {
      await h.test("Cloud.SAVE_PREF('is_dark_mode', TRUE)");
      expect(savedState['is_dark_mode'], true);
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

      // Override _ON_PREF_CHANGED to track preference changes
      h.runtime.setBinaryFunction('_ON_PREF_CHANGED', (ctx, caller, key, value) {
        prefChanges.add('$key=$value');
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
      expect(prefChanges, contains('onboarding_completed=true'));
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

    test('GET_INIT_STATE returns all prefs as object', () async {
      await h.test(r'''
        Prefs.SET_DARK_MODE(TRUE);
        Prefs.SET_ANALYTICS_CONSENT(TRUE);
        __state := Prefs.GET_INIT_STATE();
        EXPECT(__state.IS_DARK_MODE, TRUE);
        EXPECT(__state.ANALYTICS_ENABLED, TRUE);
        EXPECT(__state.ONBOARDING_COMPLETED, FALSE)
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

    test('STATS_HERO_ADDED updates running totals', () async {
      final hero =
          makeStatsHero('h1', 'Batman', heightM: 1.88, weightKg: 95.0, strength: 80);
      await h.test(r'''
        Stats.STATS_HERO_ADDED(__h);
        EXPECT(Stats.height_count, 1);
        EXPECT(Stats.weight_count, 1);
        EXPECT(Stats.total_fighting_power, 80);
        EXPECT(Stats.height_total, 1.88)
      ''', boundValues: {'__h': hero});
    });

    test('DERIVE_STATS computes avg and stdev', () async {
      final h1 =
          makeStatsHero('h1', 'Hero1', heightM: 1.80, weightKg: 80.0, strength: 50);
      final h2 =
          makeStatsHero('h2', 'Hero2', heightM: 2.00, weightKg: 100.0, strength: 70);

      await h.test(r'''
        Stats.STATS_HERO_ADDED(__h1);
        Stats.STATS_HERO_ADDED(__h2);
        EXPECT(Stats.total_fighting_power, 120)
      ''', boundValues: {'__h1': h1, '__h2': h2});

      final avg = await h.test('Stats.height_avg') as num;
      expect(avg, closeTo(1.9, 0.001));
      final stdev = await h.test('Stats.height_stdev') as num;
      expect(stdev, greaterThan(0));
    });

    test('STATS_HERO_REMOVED decrements totals', () async {
      final hero =
          makeStatsHero('h1', 'Batman', heightM: 1.88, weightKg: 95.0, strength: 80);
      await h.test(r'''
        Stats.STATS_HERO_ADDED(__h);
        Stats.STATS_HERO_REMOVED(__h);
        EXPECT(Stats.height_count, 0);
        EXPECT(Stats.total_fighting_power, 0);
        EXPECT(Stats.height_avg, 0)
      ''', boundValues: {'__h': hero});
    });

    test('STATS_HERO_REPLACED is equivalent to remove + add', () async {
      final oldHero =
          makeStatsHero('h1', 'OldHero', heightM: 1.80, weightKg: 80.0, strength: 50);
      final newHero =
          makeStatsHero('h1', 'NewHero', heightM: 2.00, weightKg: 100.0, strength: 90);

      await h.test(r'''
        Stats.STATS_HERO_ADDED(__old);
        Stats.STATS_HERO_REPLACED(__old, __new);
        EXPECT(Stats.height_count, 1);
        EXPECT(Stats.total_fighting_power, 90)
      ''', boundValues: {'__old': oldHero, '__new': newHero});

      final avg = await h.test('Stats.height_avg') as num;
      expect(avg, closeTo(2.0, 0.001));
    });

    test('STATS_CLEAR resets everything to zero', () async {
      final hero =
          makeStatsHero('h1', 'Batman', heightM: 1.88, weightKg: 95.0, strength: 80);
      await h.test(r'''
        Stats.STATS_HERO_ADDED(__h);
        Stats.STATS_CLEAR();
        EXPECT(Stats.height_count, 0);
        EXPECT(Stats.height_total, 0);
        EXPECT(Stats.weight_count, 0);
        EXPECT(Stats.weight_total, 0);
        EXPECT(Stats.total_fighting_power, 0);
        EXPECT(Stats.height_avg, 0);
        EXPECT(Stats.height_stdev, 0)
      ''', boundValues: {'__h': hero});
    });

    test('STATS_HERO_ADDED ignores null height/weight', () async {
      final hero = makeStatsHero('h1', 'NoAppearance', strength: 50);
      await h.test(r'''
        Stats.STATS_HERO_ADDED(__h);
        EXPECT(Stats.height_count, 0);
        EXPECT(Stats.weight_count, 0);
        EXPECT(Stats.total_fighting_power, 50)
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
        EXPECT(LENGTH(Filters.filters), 10);
        EXPECT(Filters.active_filter_index, -1)
      ''');
    });

    test('ON_HERO_ADDED adds hero to displayed_heroes', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        Filters.ON_HERO_ADDED(__h);
        ASSERT(LENGTH(Filters.displayed_heroes) > 0)
      ''', boundValues: {'__h': hero});
    });

    test('ON_HERO_REMOVED removes hero from displayed_heroes', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        Filters.ON_HERO_ADDED(__h);
        Filters.ON_HERO_REMOVED(__h);
        EXPECT(LENGTH(Filters.displayed_heroes), 0)
      ''', boundValues: {'__h': hero});
    });

    test('ON_CLEAR empties all filter results', () async {
      await h.test(r'''
        Filters.REBUILD_ALL_FILTERS();
        Filters.ON_CLEAR();
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

    test('__WMO_DESCRIPTION maps weather codes', () async {
      await h.test(r'''
        EXPECT(World.__WMO_DESCRIPTION(0), 'Clear sky');
        EXPECT(World.__WMO_DESCRIPTION(2), 'Partly cloudy');
        EXPECT(World.__WMO_DESCRIPTION(45), 'Foggy');
        EXPECT(World.__WMO_DESCRIPTION(55), 'Drizzle');
        EXPECT(World.__WMO_DESCRIPTION(63), 'Rain');
        EXPECT(World.__WMO_DESCRIPTION(73), 'Snow');
        EXPECT(World.__WMO_DESCRIPTION(80), 'Rain showers');
        EXPECT(World.__WMO_DESCRIPTION(85), 'Snow showers');
        EXPECT(World.__WMO_DESCRIPTION(95), 'Thunderstorm')
      ''');
    });

    test('__WMO_ICON maps weather codes to icons', () async {
      await h.test(r'''
        EXPECT(World.__WMO_ICON(0), 'wb_sunny');
        EXPECT(World.__WMO_ICON(2), 'cloud');
        EXPECT(World.__WMO_ICON(45), 'foggy');
        EXPECT(World.__WMO_ICON(55), 'water_drop');
        EXPECT(World.__WMO_ICON(73), 'ac_unit');
        EXPECT(World.__WMO_ICON(95), 'flash_on')
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
}
