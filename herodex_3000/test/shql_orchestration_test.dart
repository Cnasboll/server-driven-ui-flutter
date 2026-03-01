import 'package:flutter_test/flutter_test.dart';
import 'package:shql/testing/shql_test_runner.dart';

/// Lightweight SHQL™ stubs for dependencies that record calls.
/// Each stub records method invocations so tests can verify ordering.
const _stubs = r'''
-- Stub: Stats — records calls, no real computation
Stats := OBJECT{
    log: [],
    STATS_HERO_ADDED: (__hero) => log := log + ['added:' + __hero.NAME],
    STATS_HERO_REMOVED: (__hero) => log := log + ['removed:' + __hero.NAME],
    STATS_CLEAR: () => log := log + ['clear']
};

-- Stub: Filters — records calls, tracks displayed_heroes
Filters := OBJECT{
    log: [],
    displayed_heroes: [],
    filtered_heroes: [],
    filter_counts: [],
    active_filter_index: -1,
    current_query: '',
    ON_HERO_ADDED: (__hero) => BEGIN
        log := log + ['added:' + __hero.ID];
        displayed_heroes := displayed_heroes + [__hero];
    END,
    ON_HERO_REMOVED: (__hero) => BEGIN
        log := log + ['removed:' + __hero.ID];
        __new := [];
        IF LENGTH(displayed_heroes) > 0 THEN
            FOR __i := 0 TO LENGTH(displayed_heroes) - 1 DO
                IF displayed_heroes[__i].ID <> __hero.ID THEN
                    __new := __new + [displayed_heroes[__i]];
        displayed_heroes := __new;
    END,
    ON_CLEAR: () => BEGIN
        log := log + ['clear'];
        displayed_heroes := [];
    END,
    FULL_REBUILD: () => log := log + ['full_rebuild'],
    UPDATE_DISPLAYED_HEROES: () => null,
    GET_DISPLAY_STATE: () => OBJECT{heroes: displayed_heroes, empty_card: null}
};

-- Stub: Cards — records cache operations
Cards := OBJECT{
    log: [],
    card_cache: {},
    CACHE_HERO_CARD: (__hero) => BEGIN
        log := log + ['cache:' + __hero.ID];
        card_cache[__hero.ID] := OBJECT{id: __hero.ID, card: TRUE};
    END,
    CACHE_HERO_CARDS: (__heroes) => BEGIN
        IF __heroes <> null AND LENGTH(__heroes) > 0 THEN
            FOR __i := 0 TO LENGTH(__heroes) - 1 DO
                CACHE_HERO_CARD(__heroes[__i]);
    END,
    REMOVE_CACHED_CARD: (__id) => BEGIN
        log := log + ['remove:' + __id];
        MAP_REMOVE(card_cache, __id);
    END,
    CLEAR_CARD_CACHE: () => BEGIN
        log := log + ['clear'];
        card_cache := {};
    END
};

-- Stub: Nav — records navigation
Nav := OBJECT{
    log: [],
    current: 'home',
    GO_TO: (route) => BEGIN
        log := log + ['goto:' + route];
        current := route;
    END,
    GO_BACK: () => BEGIN
        log := log + ['back'];
        current := 'home';
    END
};

-- Stub: Prefs
Prefs := OBJECT{
    is_dark_mode: FALSE
};

-- Stub: Cloud
Cloud := OBJECT{
    SAVE_PREF: (key, value) => null
};
''';

// ─── Shared paths ───────────────────────────────────────────────────
const _shqlDir = 'assets/shql';
const _stdlibPath = '../shql/assets/stdlib.shql';
const _testLibPath = '../shql/assets/shql_test.shql';

/// Create a [ShqlTestRunner] wired to flutter_test's [expect].
ShqlTestRunner _createRunner() => ShqlTestRunner.withExpect(expect);

/// Standard setUp: create runner, load stdlib + shql_test + stubs.
Future<ShqlTestRunner> _standardSetUp() async {
  final h = _createRunner();
  await h.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);
  await h.eval(_stubs);
  return h;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // Heroes.shql tests
  // ═══════════════════════════════════════════════════════════════════
  group('Heroes', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
      h.mockUnary('_HERO_DATA_DELETE');
      h.mockUnary('_HERO_DATA_TOGGLE_LOCK', (id) {
        return h.makeObject({'locked': true});
      });
      h.mockUnary('_SHOW_SNACKBAR');

      await h.loadFile('$_shqlDir/heroes.shql');
    });

    test('ON_HERO_ADDED adds hero to map and updates total', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval(r'''
        Heroes.ON_HERO_ADDED(__h);
        EXPECT("Heroes.total_heroes", 1);
        EXPECT("Heroes.heroes['h1'].NAME", 'Batman')
      ''', boundValues: {'__h': hero});
    });

    test('ON_HERO_ADDED delegates to Stats and Filters', () async {
      final hero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});

      expect(await h.eval('Stats.log'), contains('added:Batman'));
      expect(await h.eval('Filters.log'), contains('added:h1'));
    });

    test('ON_HERO_REMOVED removes hero and delegates to Stats and Filters',
        () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});
      await h.eval('Heroes.ON_HERO_REMOVED(__h)',
          boundValues: {'__h': hero});

      await h.eval('EXPECT("Heroes.total_heroes", 0)');
      expect(await h.eval('Heroes.heroes["h1"]'), isNull);
      expect(await h.eval('Stats.log'),
          containsAllInOrder(['added:Batman', 'removed:Batman']));
      expect(await h.eval('Filters.log'),
          containsAllInOrder(['added:h1', 'removed:h1']));
    });

    test('DELETE_HERO: SHQL remove before Dart delete (stack discipline)',
        () async {
      final hero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});
      await h.eval('Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero});

      h.callLog.clear();
      await h.eval(r'''
        Heroes.DELETE_HERO('h1');
        EXPECT("Heroes.total_heroes", 0);
        ASSERT("Heroes.heroes['h1'] = null")
      ''');
      expect(await h.eval('Stats.log'), contains('removed:Batman'));
      expect(await h.eval('Filters.log'), contains('removed:h1'));
      expect(await h.eval('Cards.log'), contains('remove:h1'));

      // Dart callback was LAST (stack discipline)
      expect(h.callLog.last, '_HERO_DATA_DELETE(h1)');
    });

    test('DELETE_HERO is a no-op for unknown hero', () async {
      h.callLog.clear();
      await h.eval("Heroes.DELETE_HERO('nonexistent')");
      expect(h.callLog, isEmpty);
    });

    test('PERSIST_AND_REBUILD (new hero): just adds, no remove',
        () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval(r'''
        Heroes.PERSIST_AND_REBUILD(__h);
        EXPECT("Heroes.total_heroes", 1);
        EXPECT("Heroes.heroes['h1'].NAME", 'Batman')
      ''', boundValues: {'__h': hero});

      final statsLog = await h.eval('Stats.log') as List;
      expect(statsLog.where((e) => (e as String).startsWith('removed')),
          isEmpty);
      expect(statsLog, contains('added:Batman'));
    });

    test('PERSIST_AND_REBUILD (existing hero): removes old then adds new',
        () async {
      final oldHero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': oldHero});

      final newHero =
          h.makeObject({'id': 'h1', 'name': 'Batman (Updated)'});
      await h.eval(r'''
        Heroes.PERSIST_AND_REBUILD(__h);
        EXPECT("Heroes.total_heroes", 1);
        EXPECT("Heroes.heroes['h1'].NAME", 'Batman (Updated)')
      ''', boundValues: {'__h': newHero});

      expect(
          await h.eval('Stats.log'),
          containsAllInOrder(
              ['added:Batman', 'removed:Batman', 'added:Batman (Updated)']));
    });

    test('TOGGLE_LOCK calls Dart then updates SHQL state', () async {
      final hero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});
      await h.eval('Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero});

      h.callLog.clear();
      await h.eval(r'''
        Heroes.TOGGLE_LOCK('h1');
        ASSERT_CALLED('_HERO_DATA_TOGGLE_LOCK');
        EXPECT("Heroes.heroes['h1'].LOCKED", TRUE)
      ''');
    });

    test('ON_HERO_CLEAR resets everything', () async {
      final h1 = h.makeObject({'id': 'h1', 'name': 'Batman'});
      final h2 = h.makeObject({'id': 'h2', 'name': 'Superman'});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': h1});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': h2});

      await h.eval(r'''
        Heroes.ON_HERO_CLEAR();
        EXPECT("Heroes.total_heroes", 0);
        EXPECT("LENGTH(Heroes.heroes)", 0)
      ''');
      expect(await h.eval('Stats.log'), contains('clear'));
      expect(await h.eval('Filters.log'), contains('clear'));
      expect(await h.eval('Cards.log'), contains('clear'));
    });

    test('CLEAR_SELECTED_IF clears selected when ID matches', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Heroes.SET_SELECTED_HERO(__h)',
          boundValues: {'__h': hero});
      expect(await h.eval('Heroes.selected_hero'), isNotNull);

      await h.eval(r'''
        Heroes.CLEAR_SELECTED_IF('h1');
        ASSERT("Heroes.selected_hero = null")
      ''');
    });

    test('CLEAR_SELECTED_IF does not clear when ID differs', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Heroes.SET_SELECTED_HERO(__h)',
          boundValues: {'__h': hero});

      await h.eval("Heroes.CLEAR_SELECTED_IF('h2')");
      expect(await h.eval('Heroes.selected_hero'), isNotNull);
    });

    test('SELECT_HERO sets selected and navigates to detail', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval(r'''
        Heroes.SELECT_HERO(__h);
        EXPECT("Heroes.selected_hero.NAME", 'Batman');
        EXPECT("Nav.current", 'hero_detail')
      ''', boundValues: {'__h': hero});
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Reconciliation stack discipline tests
  // ═══════════════════════════════════════════════════════════════════
  group('Reconciliation', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
      h.mockUnary('_SHOW_SNACKBAR');
      await h.loadFile('$_shqlDir/heroes.shql');
    });

    test(
        'RECONCILE_UPDATE: SHQL remove → Dart persist → SHQL add (stack discipline)',
        () async {
      final oldHero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': oldHero});
      await h.eval('Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': oldHero});

      final updatedHero =
          h.makeObject({'id': 'h1', 'name': 'Batman v2', 'locked': false});
      final opaqueModel = 'opaque-hero-model';
      h.runtime.setUnaryFunction('_RECONCILE_PERSIST',
          (ctx, caller, model) {
        h.callLog.add('_RECONCILE_PERSIST');
        return updatedHero;
      });

      await h.eval('Stats.log := []');
      await h.eval('Filters.log := []');
      await h.eval('Cards.log := []');
      h.callLog.clear();

      await h.eval(r'''
        Heroes.RECONCILE_UPDATE(__old, __opaque, 'Updated', 'Batman: updated');
        EXPECT("Heroes.total_heroes", 1);
        EXPECT("Heroes.heroes['h1'].NAME", 'Batman v2')
      ''', boundValues: {'__old': oldHero, '__opaque': opaqueModel});

      // Stats: remove before add
      final statsLog = await h.eval('Stats.log') as List;
      final removeIdx =
          statsLog.indexWhere((e) => (e as String).startsWith('removed'));
      final addIdx =
          statsLog.indexWhere((e) => (e as String).startsWith('added'));
      expect(removeIdx, lessThan(addIdx),
          reason: 'Stats remove must precede add');

      // Filters: remove before add
      expect(await h.eval('Filters.log'),
          containsAllInOrder(['removed:h1', 'added:h1']));

      // Cards: remove old, cache new
      expect(await h.eval('Cards.log'),
          containsAllInOrder(['remove:h1', 'cache:h1']));

      // Dart persist was called
      expect(h.callLog, contains('_RECONCILE_PERSIST'));
    });

    test('RECONCILE_DELETE: SHQL remove then status log', () async {
      final hero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});

      await h.eval(r'''
        Heroes.RECONCILE_DELETE(__hero, 'Deleted', 'Batman: deleted');
        EXPECT("Heroes.total_heroes", 0);
        ASSERT("Heroes.heroes['h1'] = null")
      ''', boundValues: {'__hero': hero});
      expect(await h.eval('Cards.log'), contains('remove:h1'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Search flow tests
  // ═══════════════════════════════════════════════════════════════════
  group('Search', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
      h.mockUnary('_SHOW_SNACKBAR');
      await h.loadFile('$_shqlDir/heroes.shql');
      await h.loadFile('$_shqlDir/search.shql');
    });

    test('SEARCH_HEROES short query returns empty', () async {
      var fetchCalled = false;
      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, q) {
        fetchCalled = true;
        return null;
      });

      await h.eval(r'''
        Search.SEARCH_HEROES('a');
        EXPECT("LENGTH(Search.search_results)", 0)
      ''');
      expect(fetchCalled, false);
    });

    test('SEARCH_HEROES with all already-saved heroes', () async {
      final batman =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': batman});

      final model1 = 'opaque-batman';

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'), [model1]);
        return result;
      });

      h.runtime.setUnaryFunction('_GET_SAVED_ID', (ctx, caller, model) {
        return 'h1';
      });

      var saveCalled = false;
      h.runtime.setUnaryFunction('_SAVE_HERO', (ctx, caller, model) {
        saveCalled = true;
        return null;
      });

      await h.eval("Search.SEARCH_HEROES('batman')");

      expect(saveCalled, false,
          reason: 'Already-saved heroes should not be saved again');
      expect(await h.eval('Search.search_summary'),
          contains('already saved'));
    });

    test('SEARCH_HEROES save flow: _SAVE_HERO then PERSIST_AND_REBUILD',
        () async {
      final model1 = 'opaque-model-1';
      final savedHero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'), [model1]);
        return result;
      });

      h.runtime.setUnaryFunction(
          '_GET_SAVED_ID', (ctx, caller, model) => null);

      var saveHeroCalled = false;
      h.runtime.setUnaryFunction('_SAVE_HERO', (ctx, caller, model) {
        saveHeroCalled = true;
        return savedHero;
      });

      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) => 'save');

      await h.eval(r'''
        Search.SEARCH_HEROES('batman');
        EXPECT("Heroes.heroes['h1'].NAME", 'Batman');
        EXPECT("Heroes.total_heroes", 1);
        EXPECT("LENGTH(Search.search_results)", 1)
      ''');
      expect(saveHeroCalled, true, reason: '_SAVE_HERO should be called');
    });

    test('SEARCH_HEROES skip flow: _MAP_HERO used, not _SAVE_HERO',
        () async {
      final model1 = 'opaque-model-1';
      final mappedHero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'), [model1]);
        return result;
      });

      h.runtime.setUnaryFunction(
          '_GET_SAVED_ID', (ctx, caller, model) => null);

      var saveCalled = false;
      h.runtime.setUnaryFunction('_SAVE_HERO', (ctx, caller, model) {
        saveCalled = true;
        return null;
      });

      var mapHeroCalled = false;
      h.runtime.setUnaryFunction('_MAP_HERO', (ctx, caller, model) {
        mapHeroCalled = true;
        return mappedHero;
      });

      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) => 'skip');

      await h.eval(r'''
        Search.SEARCH_HEROES('batman');
        ASSERT("Heroes.heroes['h1'] = null");
        EXPECT("LENGTH(Search.search_results)", 1)
      ''');
      expect(saveCalled, false, reason: 'Skipped heroes should not be saved');
      expect(mapHeroCalled, true, reason: '_MAP_HERO should be called');
    });

    test('SEARCH_HEROES saveAll skips review for remaining heroes',
        () async {
      final model1 = 'opaque-1';
      final model2 = 'opaque-2';
      final hero1 =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      final hero2 =
          h.makeObject({'id': 'h2', 'name': 'Superman', 'locked': false});

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'),
            [model1, model2]);
        return result;
      });

      h.runtime.setUnaryFunction(
          '_GET_SAVED_ID', (ctx, caller, model) => null);

      var saveCount = 0;
      h.runtime.setUnaryFunction('_SAVE_HERO', (ctx, caller, model) {
        saveCount++;
        return saveCount == 1 ? hero1 : hero2;
      });

      var reviewCount = 0;
      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) {
        reviewCount++;
        return 'saveAll';
      });

      await h.eval(r'''
        Search.SEARCH_HEROES('heroes');
        EXPECT("Heroes.total_heroes", 2)
      ''');

      expect(reviewCount, 1,
          reason: 'saveAll should skip review for remaining');
      expect(saveCount, 2, reason: 'Both heroes should be saved');
    });

    test('SEARCH_HEROES cancel maps remaining unsaved heroes', () async {
      final model1 = 'opaque-1';
      final model2 = 'opaque-2';
      final mapped1 = h.makeObject({'id': 'h1', 'name': 'Batman'});
      final mapped2 = h.makeObject({'id': 'h2', 'name': 'Superman'});

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'),
            [model1, model2]);
        return result;
      });

      h.runtime.setUnaryFunction(
          '_GET_SAVED_ID', (ctx, caller, model) => null);

      var mapCount = 0;
      h.runtime.setUnaryFunction('_MAP_HERO', (ctx, caller, model) {
        mapCount++;
        return mapCount == 1 ? mapped1 : mapped2;
      });

      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) => 'cancel');

      await h.eval(r'''
        Search.SEARCH_HEROES('heroes');
        EXPECT("Heroes.total_heroes", 0);
        EXPECT("LENGTH(Search.search_results)", 2)
      ''');

      expect(mapCount, 2, reason: 'All remaining should be mapped on cancel');
      expect(await h.eval('Search.search_summary'), contains('cancelled'));
    });

    test('Each model is mapped exactly once (no double-mapping)', () async {
      final model1 = 'opaque-1';
      final hero1 =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'), [model1]);
        return result;
      });

      h.runtime.setUnaryFunction(
          '_GET_SAVED_ID', (ctx, caller, model) => null);

      var saveCount = 0;
      var mapCount = 0;
      h.runtime.setUnaryFunction('_SAVE_HERO', (ctx, caller, model) {
        saveCount++;
        return hero1;
      });
      h.runtime.setUnaryFunction('_MAP_HERO', (ctx, caller, model) {
        mapCount++;
        return hero1;
      });
      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) => 'save');

      await h.eval("Search.SEARCH_HEROES('batman')");

      expect(saveCount, 1);
      expect(mapCount, 0,
          reason: 'Saved model should not also be mapped');
    });

    test('Search history is maintained', () async {
      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        result.setVariable(
            h.constantsSet.identifiers.include('RESULTS'), <dynamic>[]);
        return result;
      });

      await h.eval(r'''
        Search.SEARCH_HEROES('batman');
        Search.SEARCH_HEROES('superman');
        EXPECT("LENGTH(Search.search_history)", 2);
        EXPECT("Search.search_history[0]", 'superman');
        EXPECT("Search.search_history[1]", 'batman')
      ''');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HeroEdit stack discipline tests
  // ═══════════════════════════════════════════════════════════════════
  group('HeroEdit', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
      h.mockUnary('_SHOW_SNACKBAR');
      await h.loadFile('$_shqlDir/heroes.shql');
      await h.loadFile('$_shqlDir/hero_edit.shql');
    });

    test(
        'SAVE_AMENDMENTS: SHQL remove → Dart amend → SHQL add (stack discipline)',
        () async {
      final hero =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});
      await h.eval('Heroes.SET_SELECTED_HERO(__h)',
          boundValues: {'__h': hero});

      final field = h.makeObject({
        'section': '',
        'label': 'Name',
        'json_section': '',
        'json_name': 'name',
        'value': 'Batman (Amended)',
        'original': 'Batman',
        'field_type': 'string',
        'options': <dynamic>[],
        'enum_names': <dynamic>[],
      });
      await h.eval('HeroEdit.SET_EDIT_FIELDS([__f])',
          boundValues: {'__f': field});

      final amendedHero = h.makeObject(
          {'id': 'h1', 'name': 'Batman (Amended)', 'locked': true});
      h.runtime.setBinaryFunction('_HERO_DATA_AMEND',
          (ctx, caller, heroId, amendment) {
        h.callLog.add('_HERO_DATA_AMEND');
        return h.makeObject({'new_obj': amendedHero, 'id': 'h1'});
      });

      await h.eval('Stats.log := []');
      await h.eval('Filters.log := []');
      await h.eval('Cards.log := []');
      h.callLog.clear();

      await h.eval('HeroEdit.SAVE_AMENDMENTS()');

      // Stats: remove before add (two transactions)
      final statsLog = await h.eval('Stats.log') as List;
      final removeIdx =
          statsLog.indexWhere((e) => (e as String).startsWith('removed'));
      final addIdx =
          statsLog.indexWhere((e) => (e as String).startsWith('added'));
      expect(removeIdx, greaterThanOrEqualTo(0), reason: 'Remove must occur');
      expect(addIdx, greaterThan(removeIdx),
          reason: 'Stats remove must precede add');

      // Filters: remove before add
      expect(await h.eval('Filters.log'),
          containsAllInOrder(['removed:h1', 'added:h1']));

      // Cards: remove old, cache new
      expect(await h.eval('Cards.log'),
          containsAllInOrder(['remove:h1', 'cache:h1']));

      // Dart amend was called
      expect(h.callLog, contains('_HERO_DATA_AMEND'));

      // Final state
      await h.eval(r'''
        EXPECT("Heroes.heroes['h1'].NAME", 'Batman (Amended)');
        EXPECT("Heroes.total_heroes", 1)
      ''');

      // Navigated back
      expect(await h.eval('Nav.log'), contains('back'));
    });

    test('SAVE_AMENDMENTS with no changes shows snackbar', () async {
      final field = h.makeObject({
        'section': '',
        'label': 'Name',
        'json_section': '',
        'json_name': 'name',
        'value': 'Batman',
        'original': 'Batman',
        'field_type': 'string',
        'options': <dynamic>[],
        'enum_names': <dynamic>[],
      });
      await h.eval('HeroEdit.SET_EDIT_FIELDS([__f])',
          boundValues: {'__f': field});

      var amendCalled = false;
      h.runtime.setBinaryFunction('_HERO_DATA_AMEND',
          (ctx, caller, heroId, amendment) {
        amendCalled = true;
        return null;
      });

      h.callLog.clear();
      await h.eval('HeroEdit.SAVE_AMENDMENTS()');

      expect(amendCalled, false,
          reason: 'No Dart amend for unchanged fields');
      expect(h.callLog, contains('_SHOW_SNACKBAR(No changes made)'));
    });

    test('BUILD_AMENDMENT only includes changed fields', () async {
      final f1 = h.makeObject({
        'section': '',
        'label': 'Name',
        'json_section': '',
        'json_name': 'name',
        'value': 'Batman (Changed)',
        'original': 'Batman',
        'field_type': 'string',
        'options': <dynamic>[],
        'enum_names': <dynamic>[],
      });
      final f2 = h.makeObject({
        'section': '',
        'label': 'Full Name',
        'json_section': '',
        'json_name': 'full_name',
        'value': 'Bruce Wayne',
        'original': 'Bruce Wayne',
        'field_type': 'string',
        'options': <dynamic>[],
        'enum_names': <dynamic>[],
      });
      await h.eval('HeroEdit.SET_EDIT_FIELDS([__f1, __f2])',
          boundValues: {'__f1': f1, '__f2': f2});

      final amendment = await h.eval('HeroEdit.BUILD_AMENDMENT()');
      expect(amendment, isNotNull);
      expect(amendment, isA<Map>());

      final map = amendment as Map;
      expect(map['name'], 'Batman (Changed)');
      expect(map.containsKey('full_name'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Navigation tests
  // ═══════════════════════════════════════════════════════════════════
  group('Navigation', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();
      await h.loadFile('$_shqlDir/navigation.shql');
    });

    test('GO_TO pushes route and navigates', () async {
      await h.eval(r'''
        Nav.GO_TO('heroes');
        ASSERT("INDEX_OF(Nav.navigation_stack, 'heroes') >= 0")
      ''');
    });

    test('GO_TO does not duplicate route already in stack', () async {
      await h.eval(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('heroes')
      ''');
      final stack = await h.eval('Nav.navigation_stack') as List;
      expect(stack.where((e) => e == 'heroes').length, 1);
    });

    test('GO_BACK pops and navigates to previous route', () async {
      await h.eval(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('hero_detail');
        EXPECT("Nav.GO_BACK()", 'heroes');
        EXPECT("Nav.navigation_stack", ['home', 'heroes'])
      ''');
    });

    test('GO_BACK from root returns home', () async {
      await h.eval('EXPECT("Nav.GO_BACK()", \'home\')');
    });

    test('PUSH_ROUTE truncates stack when route already exists', () async {
      await h.eval(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('hero_detail');
        Nav.PUSH_ROUTE('heroes')
      ''');
      final stack = await h.eval('Nav.navigation_stack') as List;
      expect(stack.last, isNot('hero_detail'));
    });

    test('POP_ROUTE removes last entry', () async {
      await h.eval(r'''
        Nav.GO_TO('heroes');
        Nav.GO_TO('settings');
        EXPECT("Nav.POP_ROUTE()", 'heroes')
      ''');
    });

    test('TAB_NAV navigates when index differs from current', () async {
      await h.eval(r'''
        Nav.TAB_NAV(0, 2);
        ASSERT("INDEX_OF(Nav.navigation_stack, 'heroes') >= 0")
      ''');
    });

    test('TAB_NAV is no-op when index matches current', () async {
      final stackBefore = await h.eval('Nav.navigation_stack') as List;
      await h.eval('Nav.TAB_NAV(0, 0)');
      final stackAfter = await h.eval('Nav.navigation_stack') as List;
      expect(stackAfter, stackBefore);
    });

    test('CAN_GO_BACK returns false at root', () async {
      await h.eval('EXPECT("Nav.CAN_GO_BACK()", FALSE)');
    });

    test('CAN_GO_BACK returns true with stacked routes', () async {
      await h.eval(r'''
        Nav.GO_TO('heroes');
        EXPECT("Nav.CAN_GO_BACK()", TRUE)
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
      h = _createRunner();
      savedState = {};

      // Use standard setUp, then override state functions
      await h.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);
      h.runtime.saveStateFunction = (key, value) async {
        savedState[key] = value;
      };
      h.runtime.loadStateFunction =
          (key, defaultValue) async => savedState[key] ?? defaultValue;

      // Cloud stub — auth.shql calls Cloud.SET_AUTH_UID
      await h.eval(r'''
        Cloud := OBJECT{
            log: [],
            auth_uid: '',
            SET_AUTH_UID: (uid) => BEGIN auth_uid := uid; log := log + ['set_uid:' + uid]; END,
            SAVE_PREF: (key, value) => null
        }
      ''');

      await h.loadFile('$_shqlDir/auth.shql');
    });

    test('__FIREBASE_ERROR_MSG maps known codes', () async {
      expect(await h.eval("Auth.__FIREBASE_ERROR_MSG('EMAIL_NOT_FOUND')"),
          contains('No account'));
      expect(await h.eval("Auth.__FIREBASE_ERROR_MSG('INVALID_PASSWORD')"),
          contains('Incorrect'));
      expect(
          await h.eval("Auth.__FIREBASE_ERROR_MSG('INVALID_LOGIN_CREDENTIALS')"),
          contains('Invalid email'));
    });

    test('__FIREBASE_ERROR_MSG returns code for unknown errors', () async {
      await h.eval(r'''
        EXPECT("Auth.__FIREBASE_ERROR_MSG('SOME_UNKNOWN')", 'SOME_UNKNOWN')
      ''');
    });

    test('__FIREBASE_ERROR_MSG matches WEAK_PASSWORD with tilde', () async {
      expect(
          await h
              .eval("Auth.__FIREBASE_ERROR_MSG('WEAK_PASSWORD : some detail')"),
          contains('6 characters'));
    });

    test('__FIREBASE_EXTRACT_ERROR handles null body', () async {
      await h.eval(r'''
        EXPECT("Auth.__FIREBASE_EXTRACT_ERROR(null)", 'Unknown error')
      ''');
    });

    test('__FIREBASE_EXTRACT_ERROR extracts nested error message', () async {
      final body = <String, dynamic>{
        'error': <String, dynamic>{'message': 'EMAIL_NOT_FOUND'}
      };
      final result = await h.eval('Auth.__FIREBASE_EXTRACT_ERROR(__body)',
          boundValues: {'__body': body});
      expect(result, contains('No account'));
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
          await h.eval("Auth.FIREBASE_SIGN_IN('a@b.com', 'pass123')");
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
          await h.eval("Auth.FIREBASE_SIGN_IN('a@b.com', 'wrong')");
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

      await h.eval("Auth.FIREBASE_SIGN_UP('a@b.com', 'pass')");
      expect(calledUrl, contains('signUp'));
    });

    test('FIREBASE_SIGN_OUT clears saved state', () async {
      savedState['_auth_id_token'] = 'tok';
      savedState['_auth_email'] = 'a@b.com';
      savedState['_auth_uid'] = 'uid';
      savedState['_auth_refresh_token'] = 'ref';

      await h.eval('Auth.FIREBASE_SIGN_OUT()');

      expect(savedState['_auth_id_token'], isNull);
      expect(savedState['_auth_email'], isNull);
      expect(savedState['_auth_uid'], isNull);
      expect(savedState['_auth_refresh_token'], isNull);
    });

    test('FIREBASE_REFRESH_TOKEN returns empty when no refresh token',
        () async {
      await h.eval("EXPECT(\"Auth.FIREBASE_REFRESH_TOKEN()\", '')");
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

      await h.eval("EXPECT(\"Auth.FIREBASE_REFRESH_TOKEN()\", 'new_tok')");
      expect(savedState['_auth_id_token'], 'new_tok');
      expect(savedState['_auth_refresh_token'], 'new_ref');
    });

    test('LOGIN_SUBMIT rejects empty email', () async {
      await h.eval(r'''
        Auth.LOGIN_EMAIL := '';
        Auth.LOGIN_PASSWORD := 'pass';
        Auth.LOGIN_SUBMIT();
        EXPECT("Auth.LOGIN_IS_LOADING", FALSE)
      ''');
      expect(await h.eval('Auth.LOGIN_ERROR'), contains('email and password'));
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

      await h.eval(r'''
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

      await h.eval(r'''
        Auth.LOGIN_EMAIL := 'a@b.com';
        Auth.LOGIN_PASSWORD := 'wrong';
        Auth.LOGIN_SUBMIT();
        EXPECT("Auth.LOGIN_IS_LOADING", FALSE)
      ''');
      expect(await h.eval('Auth.LOGIN_ERROR'), contains('Incorrect'));
    });

    test('LOGIN_TOGGLE_MODE toggles register flag and clears error', () async {
      await h.eval(r'''
        Auth.SET_LOGIN_ERROR('some error');
        EXPECT("Auth.LOGIN_IS_REGISTERING", FALSE);
        Auth.LOGIN_TOGGLE_MODE();
        EXPECT("Auth.LOGIN_IS_REGISTERING", TRUE);
        EXPECT("Auth.LOGIN_ERROR", '');
        Auth.LOGIN_TOGGLE_MODE();
        EXPECT("Auth.LOGIN_IS_REGISTERING", FALSE)
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
      h = _createRunner();
      savedState = {};

      // Use standard setUp, then override state functions
      await h.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);
      h.runtime.saveStateFunction = (key, value) async {
        savedState[key] = value;
      };
      h.runtime.loadStateFunction =
          (key, defaultValue) async => savedState[key] ?? defaultValue;

      // Auth stub required by firestore.shql
      await h.eval(r'''
        Auth := OBJECT{
            FIREBASE_API_KEY: 'test-key',
            FIREBASE_PROJECT_ID: 'test-project',
            FIREBASE_REFRESH_TOKEN: () => 'refreshed-token'
        }
      ''');

      // NUMBER() is used in firestore.shql but not defined in stdlib
      h.runtime.setUnaryFunction('NUMBER', (ctx, caller, a) {
        if (a is int) return a;
        if (a is String) return int.tryParse(a) ?? double.tryParse(a) ?? 0;
        if (a is double) return a;
        return a;
      });

      await h.loadFile('$_shqlDir/firestore.shql');
    });

    test('__TO_VALUE converts booleans', () async {
      final r = await h.eval('Cloud.__TO_VALUE(TRUE)');
      expect(r, isA<Map>());
      expect((r as Map)['booleanValue'], true);
    });

    test('__TO_VALUE converts strings', () async {
      final r = await h.eval("Cloud.__TO_VALUE('hello')") as Map;
      expect(r['stringValue'], 'hello');
    });

    test('__FROM_VALUE converts boolean values', () async {
      await h.eval('EXPECT("Cloud.__FROM_VALUE({\'booleanValue\': TRUE})", TRUE)');
    });

    test('__FROM_VALUE converts integer values', () async {
      final r =
          await h.eval('Cloud.__FROM_VALUE({"integerValue": "42"})');
      expect(r, 42);
    });

    test('__FROM_VALUE converts string values', () async {
      await h.eval(r'''
        EXPECT("Cloud.__FROM_VALUE({'stringValue': 'hello'})", 'hello')
      ''');
    });

    test('__FROM_VALUE returns null for unknown types', () async {
      await h.eval('ASSERT("Cloud.__FROM_VALUE({}) = null")');
    });

    test('SET_AUTH_UID updates uid', () async {
      await h.eval(r'''
        Cloud.SET_AUTH_UID('user123');
        EXPECT("Cloud.auth_uid", 'user123')
      ''');
    });

    test('SAVE skips when auth_uid is empty', () async {
      var patchCalled = false;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, a, b, c) {
        patchCalled = true;
        return <String, dynamic>{'status': 200};
      });

      await h.eval("Cloud.SAVE('is_dark_mode', TRUE)");
      expect(patchCalled, false);
    });

    test('SAVE skips when key not in SYNCED_KEYS', () async {
      await h.eval("Cloud.SET_AUTH_UID('uid1')");
      savedState['_auth_id_token'] = 'tok';

      var patchCalled = false;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, a, b, c) {
        patchCalled = true;
        return <String, dynamic>{'status': 200};
      });

      await h.eval("Cloud.SAVE('not_synced_key', 'value')");
      expect(patchCalled, false);
    });

    test('SAVE calls PATCH_AUTH with correct URL', () async {
      await h.eval("Cloud.SET_AUTH_UID('uid1')");
      savedState['_auth_id_token'] = 'tok';

      String? calledUrl;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, url, body, token) {
        calledUrl = url as String;
        return <String, dynamic>{'status': 200};
      });

      await h.eval("Cloud.SAVE('is_dark_mode', TRUE)");
      expect(calledUrl, contains('test-project'));
      expect(calledUrl, contains('uid1'));
      expect(calledUrl, contains('is_dark_mode'));
    });

    test('SAVE retries with refresh on 401', () async {
      await h.eval("Cloud.SET_AUTH_UID('uid1')");
      savedState['_auth_id_token'] = 'tok';

      var callCount = 0;
      h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, caller, url, body, token) {
        callCount++;
        if (callCount == 1) return <String, dynamic>{'status': 401};
        return <String, dynamic>{'status': 200};
      });

      await h.eval("Cloud.SAVE('is_dark_mode', TRUE)");
      expect(callCount, 2, reason: 'Should retry after 401');
    });

    test('LOAD_ALL returns empty map when no uid', () async {
      final r = await h.eval('Cloud.LOAD_ALL()');
      expect(r, isA<Map>());
      expect((r as Map).isEmpty, true);
    });

    test('LOAD_ALL parses Firestore fields', () async {
      await h.eval("Cloud.SET_AUTH_UID('uid1')");
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

      final r = await h.eval('Cloud.LOAD_ALL()') as Map;
      expect(r['is_dark_mode'], true);
      expect(r['api_key'], 'mykey');
      expect(r.containsKey('unknown_key'), false,
          reason: 'Only SYNCED_KEYS are returned');
    });

    test('SAVE_PREF saves locally and to cloud', () async {
      await h.eval("Cloud.SAVE_PREF('is_dark_mode', TRUE)");
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

      // Nav stub needed by RESET_ONBOARDING
      await h.loadFile('$_shqlDir/navigation.shql');

      // _ON_PREF_CHANGED callback
      h.runtime.setBinaryFunction('_ON_PREF_CHANGED', (ctx, caller, key, value) {
        prefChanges.add('$key=$value');
        return null;
      });

      await h.loadFile('$_shqlDir/preferences.shql');
    });

    test('TOGGLE_DARK_MODE flips dark mode', () async {
      await h.eval(r'''
        EXPECT("Prefs.is_dark_mode", FALSE);
        Prefs.TOGGLE_DARK_MODE();
        EXPECT("Prefs.is_dark_mode", TRUE)
      ''');
      expect(prefChanges, contains('is_dark_mode=true'));

      await h.eval(r'''
        Prefs.TOGGLE_DARK_MODE();
        EXPECT("Prefs.is_dark_mode", FALSE)
      ''');
    });

    test('SET_DARK_MODE sets explicit value', () async {
      await h.eval(r'''
        Prefs.SET_DARK_MODE(TRUE);
        EXPECT("Prefs.is_dark_mode", TRUE)
      ''');
      expect(prefChanges, contains('is_dark_mode=true'));
    });

    test('SET_ANALYTICS_CONSENT saves and notifies', () async {
      await h.eval(r'''
        Prefs.SET_ANALYTICS_CONSENT(TRUE);
        EXPECT("Prefs.analytics_enabled", TRUE)
      ''');
      expect(prefChanges, contains('analytics_enabled=true'));
    });

    test('SET_CRASHLYTICS_CONSENT saves and notifies', () async {
      await h.eval(r'''
        Prefs.SET_CRASHLYTICS_CONSENT(TRUE);
        EXPECT("Prefs.crashlytics_enabled", TRUE)
      ''');
      expect(prefChanges, contains('crashlytics_enabled=true'));
    });

    test('SET_LOCATION_CONSENT saves and notifies', () async {
      await h.eval(r'''
        Prefs.SET_LOCATION_CONSENT(TRUE);
        EXPECT("Prefs.location_enabled", TRUE)
      ''');
      expect(prefChanges, contains('location_enabled=true'));
    });

    test('COMPLETE_ONBOARDING sets flag to true', () async {
      await h.eval(r'''
        Prefs.COMPLETE_ONBOARDING();
        EXPECT("Prefs.onboarding_completed", TRUE)
      ''');
      expect(prefChanges, contains('onboarding_completed=true'));
    });

    test('IS_ONBOARDING_COMPLETED returns current value', () async {
      await h.eval(r'''
        EXPECT("Prefs.IS_ONBOARDING_COMPLETED()", FALSE);
        Prefs.COMPLETE_ONBOARDING();
        EXPECT("Prefs.IS_ONBOARDING_COMPLETED()", TRUE)
      ''');
    });

    test('RESET_ONBOARDING clears flag and navigates to onboarding', () async {
      await h.eval(r'''
        Prefs.COMPLETE_ONBOARDING();
        Prefs.RESET_ONBOARDING();
        EXPECT("Prefs.onboarding_completed", FALSE)
      ''');
      final stack = await h.eval('Nav.navigation_stack') as List;
      expect(stack, contains('onboarding'));
    });

    test('SET_API_KEY stores key', () async {
      await h.eval(r'''
        Prefs.SET_API_KEY('mykey123');
        EXPECT("Prefs.api_key", 'mykey123')
      ''');
    });

    test('SET_API_HOST stores host', () async {
      await h.eval(r'''
        Prefs.SET_API_HOST('custom.api.com');
        EXPECT("Prefs.api_host", 'custom.api.com')
      ''');
    });

    test('GET_INIT_STATE returns all prefs as object', () async {
      await h.eval('Prefs.SET_DARK_MODE(TRUE)');
      await h.eval('Prefs.SET_ANALYTICS_CONSENT(TRUE)');

      final state = await h.eval('Prefs.GET_INIT_STATE()');
      expect(h.readField(state, 'is_dark_mode'), true);
      expect(h.readField(state, 'analytics_enabled'), true);
      expect(h.readField(state, 'onboarding_completed'), false);
    });

    test('GET_API_CREDENTIALS returns cached values', () async {
      await h.eval("Prefs.SET_API_KEY('mykey')");
      await h.eval("Prefs.SET_API_HOST('myhost.com')");

      final creds = await h.eval('Prefs.GET_API_CREDENTIALS()');
      expect(h.readField(creds, 'api_key'), 'mykey');
      expect(h.readField(creds, 'api_host'), 'myhost.com');
    });

    test('GET_API_CREDENTIALS prompts when key is empty', () async {
      h.runtime.setBinaryFunction('_PROMPT', (ctx, caller, prompt, defaultVal) {
        h.callLog.add('_PROMPT');
        return 'prompted_key';
      });

      final creds = await h.eval('Prefs.GET_API_CREDENTIALS()');
      expect(h.readField(creds, 'api_key'), 'prompted_key');
      expect(h.callLog, contains('_PROMPT'));
    });

    test('GET_API_CREDENTIALS returns null when user cancels prompt',
        () async {
      h.runtime.setBinaryFunction('_PROMPT', (ctx, caller, prompt, defaultVal) {
        return null;
      });

      final creds = await h.eval('Prefs.GET_API_CREDENTIALS()');
      expect(creds, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Statistics tests
  // ═══════════════════════════════════════════════════════════════════
  group('Statistics', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();

      // Register accessor stubs using readField helper
      h.runtime.setBinaryFunction('HEIGHT_M', (ctx, caller, hero, defaultVal) {
        final v = h.readField(hero, 'HEIGHT');
        return v ?? defaultVal;
      });
      h.runtime.setBinaryFunction('WEIGHT_KG', (ctx, caller, hero, defaultVal) {
        final v = h.readField(hero, 'WEIGHT');
        return v ?? defaultVal;
      });
      h.runtime.setTernaryFunction('POWERSTATS',
          (ctx, caller, hero, accessor, defaultVal) {
        final v = h.readField(hero, 'STRENGTH');
        return v ?? defaultVal;
      });

      await h.loadFile('$_shqlDir/statistics.shql');
    });

    test('STATS_HERO_ADDED updates running totals', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'height': 1.88,
        'weight': 95.0,
        'strength': 80
      });
      await h.eval(r'''
        Stats.STATS_HERO_ADDED(__h);
        EXPECT("Stats.height_count", 1);
        EXPECT("Stats.weight_count", 1);
        EXPECT("Stats.total_fighting_power", 80)
      ''', boundValues: {'__h': hero});
      expect(await h.eval('Stats.height_total'), 1.88);
    });

    test('DERIVE_STATS computes avg and stdev', () async {
      final h1 = h.makeObject(
          {'id': 'h1', 'height': 1.80, 'weight': 80.0, 'strength': 50});
      final h2 = h.makeObject(
          {'id': 'h2', 'height': 2.00, 'weight': 100.0, 'strength': 70});

      await h.eval('Stats.STATS_HERO_ADDED(__h)',
          boundValues: {'__h': h1});
      await h.eval(r'''
        Stats.STATS_HERO_ADDED(__h);
        EXPECT("Stats.total_fighting_power", 120)
      ''', boundValues: {'__h': h2});

      final avg = await h.eval('Stats.height_avg') as num;
      expect(avg, closeTo(1.9, 0.001));
      final stdev = await h.eval('Stats.height_stdev') as num;
      expect(stdev, greaterThan(0));
    });

    test('STATS_HERO_REMOVED decrements totals', () async {
      final hero = h.makeObject(
          {'id': 'h1', 'height': 1.88, 'weight': 95.0, 'strength': 80});
      await h.eval('Stats.STATS_HERO_ADDED(__h)',
          boundValues: {'__h': hero});
      await h.eval(r'''
        Stats.STATS_HERO_REMOVED(__h);
        EXPECT("Stats.height_count", 0);
        EXPECT("Stats.total_fighting_power", 0);
        EXPECT("Stats.height_avg", 0)
      ''', boundValues: {'__h': hero});
    });

    test('STATS_HERO_REPLACED is equivalent to remove + add', () async {
      final oldHero = h.makeObject(
          {'id': 'h1', 'height': 1.80, 'weight': 80.0, 'strength': 50});
      final newHero = h.makeObject(
          {'id': 'h1', 'height': 2.00, 'weight': 100.0, 'strength': 90});

      await h.eval('Stats.STATS_HERO_ADDED(__h)',
          boundValues: {'__h': oldHero});
      await h.eval(r'''
        Stats.STATS_HERO_REPLACED(__old, __new);
        EXPECT("Stats.height_count", 1);
        EXPECT("Stats.total_fighting_power", 90)
      ''', boundValues: {'__old': oldHero, '__new': newHero});

      final avg = await h.eval('Stats.height_avg') as num;
      expect(avg, closeTo(2.0, 0.001));
    });

    test('STATS_CLEAR resets everything to zero', () async {
      final hero = h.makeObject(
          {'id': 'h1', 'height': 1.88, 'weight': 95.0, 'strength': 80});
      await h.eval('Stats.STATS_HERO_ADDED(__h)',
          boundValues: {'__h': hero});

      await h.eval(r'''
        Stats.STATS_CLEAR();
        EXPECT("Stats.height_count", 0);
        EXPECT("Stats.height_total", 0);
        EXPECT("Stats.weight_count", 0);
        EXPECT("Stats.weight_total", 0);
        EXPECT("Stats.total_fighting_power", 0);
        EXPECT("Stats.height_avg", 0);
        EXPECT("Stats.height_stdev", 0)
      ''');
    });

    test('STATS_HERO_ADDED ignores null height/weight', () async {
      final hero = h.makeObject({'id': 'h1', 'strength': 50});
      await h.eval(r'''
        Stats.STATS_HERO_ADDED(__h);
        EXPECT("Stats.height_count", 0);
        EXPECT("Stats.weight_count", 0);
        EXPECT("Stats.total_fighting_power", 50)
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
      h.mockUnary('_SHOW_SNACKBAR');

      // Minimal Heroes stub
      await h.eval(r'''
        Heroes := OBJECT{
            heroes: {},
            total_heroes: 0,
            hero_cards: [],
            ON_HERO_ADDED: (__hero) => BEGIN
                heroes[__hero.ID] := __hero;
                total_heroes := LENGTH(heroes);
            END,
            SET_HERO_CARDS: (value) => hero_cards := value,
            REBUILD_CARDS: () => null,
            FULL_REBUILD_AND_DISPLAY: () => null
        }
      ''');

      h.runtime.setTernaryFunction('_EVAL_PREDICATE',
          (ctx, caller, hero, pred, predText) => true);

      h.runtime.setNullaryFunction('_COMPILE_FILTERS', (ctx, caller) => null);
      h.runtime.setUnaryFunction('_COMPILE_QUERY',
          (ctx, caller, query) => null);

      await h.loadFile('$_shqlDir/filters.shql');
    });

    test('Default filters are loaded', () async {
      final filters = await h.eval('Filters.filters') as List;
      expect(filters.length, greaterThanOrEqualTo(10));
    });

    test('APPLY_FILTER sets active index and updates display', () async {
      await h.eval(r'''
        Filters.REBUILD_ALL_FILTERS();
        Filters.APPLY_FILTER(0);
        EXPECT("Filters.active_filter_index", 0);
        EXPECT("Filters.current_query", '')
      ''');
    });

    test('APPLY_FILTER with -1 shows all heroes', () async {
      await h.eval(r'''
        Filters.APPLY_FILTER(-1);
        EXPECT("Filters.active_filter_index", -1)
      ''');
    });

    test('SAVE_FILTER updates existing filter by name', () async {
      await h.eval("Filters.SAVE_FILTER('Heroes', 'new predicate')");

      final filters = await h.eval('Filters.filters') as List;
      var found = false;
      for (final f in filters) {
        if (f is Object) {
          final pred = h.readField(f, 'predicate');
          final name = h.readField(f, 'name');
          if (name == 'Heroes') {
            expect(pred, 'new predicate');
            found = true;
          }
        }
      }
      expect(found, true, reason: 'Heroes filter should still exist');
    });

    test('SAVE_FILTER adds new filter when name not found', () async {
      final countBefore = (await h.eval('Filters.filters') as List).length;
      await h.eval("Filters.SAVE_FILTER('Custom', 'x > 5')");
      final countAfter = (await h.eval('Filters.filters') as List).length;
      expect(countAfter, countBefore + 1);
    });

    test('DELETE_FILTER removes filter at index', () async {
      final countBefore = (await h.eval('Filters.filters') as List).length;
      await h.eval('Filters.DELETE_FILTER(0)');
      final countAfter = (await h.eval('Filters.filters') as List).length;
      expect(countAfter, countBefore - 1);
    });

    test('DELETE_FILTER is no-op for out of range', () async {
      final countBefore = (await h.eval('Filters.filters') as List).length;
      await h.eval('Filters.DELETE_FILTER(-1)');
      await h.eval('Filters.DELETE_FILTER(999)');
      final countAfter = (await h.eval('Filters.filters') as List).length;
      expect(countAfter, countBefore);
    });

    test('ADD_FILTER adds empty filter and selects it', () async {
      final countBefore = (await h.eval('Filters.filters') as List).length;
      await h.eval('Filters.ADD_FILTER()');
      final countAfter = (await h.eval('Filters.filters') as List).length;
      expect(countAfter, countBefore + 1);
      expect(await h.eval('Filters.active_filter_index'), countAfter - 1);
    });

    test('RENAME_FILTER changes name at index', () async {
      await h.eval("Filters.RENAME_FILTER(0, 'Good Guys')");

      final filters = await h.eval('Filters.filters') as List;
      expect(h.readField(filters[0], 'name'), 'Good Guys');
    });

    test('RENAME_FILTER is no-op for out of range', () async {
      final firstBefore = h.readField(
          (await h.eval('Filters.filters') as List)[0], 'name');
      await h.eval("Filters.RENAME_FILTER(-1, 'Fail')");
      await h.eval("Filters.RENAME_FILTER(999, 'Fail')");
      final firstAfter = h.readField(
          (await h.eval('Filters.filters') as List)[0], 'name');
      expect(firstAfter, firstBefore);
    });

    test('RESET_PREDICATES restores default filters', () async {
      await h.eval(r'''
        Filters.DELETE_FILTER(0);
        Filters.RESET_PREDICATES();
        EXPECT("LENGTH(Filters.filters)", 10);
        EXPECT("Filters.active_filter_index", -1)
      ''');
    });

    test('ON_HERO_ADDED adds hero to displayed_heroes', () async {
      await h.eval('Filters.REBUILD_ALL_FILTERS()');

      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Filters.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});

      final displayed = await h.eval('Filters.displayed_heroes') as List;
      expect(displayed, isNotEmpty);
    });

    test('ON_HERO_REMOVED removes hero from displayed_heroes', () async {
      await h.eval('Filters.REBUILD_ALL_FILTERS()');

      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Filters.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});
      await h.eval('Filters.ON_HERO_REMOVED(__h)',
          boundValues: {'__h': hero});

      final displayed = await h.eval('Filters.displayed_heroes') as List;
      expect(displayed, isEmpty);
    });

    test('ON_CLEAR empties all filter results', () async {
      await h.eval('Filters.REBUILD_ALL_FILTERS()');
      await h.eval('Filters.ON_CLEAR()');

      final counts = await h.eval('Filters.filter_counts') as List;
      for (final c in counts) {
        expect(c, 0);
      }
    });

    test('GET_DISPLAY_STATE returns empty message when no heroes match',
        () async {
      await h.eval("Filters.SET_CURRENT_QUERY('xyz')");
      final state = await h.eval('Filters.GET_DISPLAY_STATE()');
      final heroes = h.readField(state, 'heroes') as List;
      final emptyCard = h.readField(state, 'empty_card');
      expect(heroes, isEmpty);
      expect(emptyCard, isNotNull);
    });

    test('GET_EDITOR_STATE returns filter state', () async {
      await h.eval('Filters.REBUILD_ALL_FILTERS()');
      final state = await h.eval('Filters.GET_EDITOR_STATE()');
      expect(h.readField(state, 'filters'), isA<List>());
      expect(h.readField(state, 'active_filter_index'), -1);
    });

    test('APPLY_QUERY sets query and triggers rebuild', () async {
      await h.eval(r'''
        Filters.APPLY_QUERY('test');
        EXPECT("Filters.current_query", 'test');
        EXPECT("Filters.active_filter_index", -1)
      ''');
    });

    test('GENERATE_FILTER_COUNTER_CARDS returns card list', () async {
      await h.eval('Filters.REBUILD_ALL_FILTERS()');
      final cards =
          await h.eval('Filters.GENERATE_FILTER_COUNTER_CARDS()') as List;
      expect(cards.length, greaterThanOrEqualTo(10));

      final firstCard = cards[0] as Map;
      expect(firstCard['type'], 'Card');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // World tests
  // ═══════════════════════════════════════════════════════════════════
  group('World', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();

      // Register alignment constants (enum ordinals)
      final cs = h.constantsSet;
      cs.registerConstant(0, cs.includeIdentifier('UNKNOWN'));
      cs.registerConstant(1, cs.includeIdentifier('NEUTRAL'));
      cs.registerConstant(2, cs.includeIdentifier('MOSTLYGOOD'));
      cs.registerConstant(3, cs.includeIdentifier('GOOD'));
      cs.registerConstant(4, cs.includeIdentifier('REASONABLE'));
      cs.registerConstant(5, cs.includeIdentifier('NOTQUITE'));
      cs.registerConstant(6, cs.includeIdentifier('BAD'));
      cs.registerConstant(7, cs.includeIdentifier('UGLY'));
      cs.registerConstant(8, cs.includeIdentifier('EVIL'));

      // Heroes stub for battle map
      await h.eval(r'''
        Heroes := OBJECT{
            heroes: {},
            total_heroes: 0
        }
      ''');

      // BIOGRAPHY and NVL stubs
      h.runtime.setTernaryFunction('NVL', (ctx, caller, val, fn, defaultVal) {
        if (val == null) return defaultVal;
        return val;
      });
      h.runtime.setTernaryFunction('BIOGRAPHY',
          (ctx, caller, hero, accessor, defaultVal) => defaultVal);

      // FETCH stub for weather
      h.runtime.setUnaryFunction('FETCH', (ctx, caller, url) => null);

      await h.loadFile('$_shqlDir/world.shql');
    });

    test('SET_LOCATION_DESCRIPTION updates description', () async {
      await h.eval(r'''
        World.SET_LOCATION_DESCRIPTION('New York');
        EXPECT("World.location_description", 'New York')
      ''');
    });

    test('SET_USER_COORDINATES updates lat and lon', () async {
      await h.eval(r'''
        World.SET_USER_COORDINATES(40.7, -74.0);
        EXPECT("World.user_latitude", 40.7);
        EXPECT("World.user_longitude", -74.0)
      ''');
    });

    test('SET_LOCATION sets description and coordinates', () async {
      await h.eval(r'''
        World.SET_LOCATION('Paris', 48.85, 2.35);
        EXPECT("World.location_description", 'Paris');
        EXPECT("World.user_latitude", 48.85);
        EXPECT("World.user_longitude", 2.35)
      ''');
    });

    test('SET_LOCATION with null coordinates only sets description',
        () async {
      await h.eval(r'''
        World.SET_USER_COORDINATES(10.0, 20.0);
        World.SET_LOCATION('Unknown', null, null);
        EXPECT("World.location_description", 'Unknown');
        EXPECT("World.user_latitude", 10.0);
        EXPECT("World.user_longitude", 20.0)
      ''');
    });

    test('__WMO_DESCRIPTION maps weather codes', () async {
      await h.eval(r'''
        EXPECT("World.__WMO_DESCRIPTION(0)", 'Clear sky');
        EXPECT("World.__WMO_DESCRIPTION(2)", 'Partly cloudy');
        EXPECT("World.__WMO_DESCRIPTION(45)", 'Foggy');
        EXPECT("World.__WMO_DESCRIPTION(55)", 'Drizzle');
        EXPECT("World.__WMO_DESCRIPTION(63)", 'Rain');
        EXPECT("World.__WMO_DESCRIPTION(73)", 'Snow');
        EXPECT("World.__WMO_DESCRIPTION(80)", 'Rain showers');
        EXPECT("World.__WMO_DESCRIPTION(85)", 'Snow showers');
        EXPECT("World.__WMO_DESCRIPTION(95)", 'Thunderstorm')
      ''');
    });

    test('__WMO_ICON maps weather codes to icons', () async {
      await h.eval(r'''
        EXPECT("World.__WMO_ICON(0)", 'wb_sunny');
        EXPECT("World.__WMO_ICON(2)", 'cloud');
        EXPECT("World.__WMO_ICON(45)", 'foggy');
        EXPECT("World.__WMO_ICON(55)", 'water_drop');
        EXPECT("World.__WMO_ICON(73)", 'ac_unit');
        EXPECT("World.__WMO_ICON(95)", 'flash_on')
      ''');
    });

    test('SET_WEATHER sets all weather properties', () async {
      await h.eval(r'''
        World.SET_WEATHER(22.5, 15.0, 'Sunny', 'wb_sunny');
        EXPECT("World.weather_temp", 22.5);
        EXPECT("World.weather_wind", 15.0);
        EXPECT("World.weather_description", 'Sunny');
        EXPECT("World.weather_icon", 'wb_sunny')
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

      await h.eval(r'''
        World.REFRESH_WEATHER();
        EXPECT("World.weather_temp", 18.5);
        EXPECT("World.weather_wind", 12.3);
        EXPECT("World.weather_description", 'Clear sky');
        EXPECT("World.weather_icon", 'wb_sunny')
      ''');
    });

    test('REFRESH_WEATHER handles null response', () async {
      h.runtime.setUnaryFunction('FETCH', (ctx, caller, url) => null);

      await h.eval(r'''
        World.REFRESH_WEATHER();
        EXPECT("World.weather_icon", 'cloud')
      ''');
    });

    test('GET_WAR_STATUS returns message based on hero count', () async {
      final msg = await h.eval('World.GET_WAR_STATUS()');
      expect(msg, isA<String>());
      expect((msg as String).isNotEmpty, true);
    });

    test('GENERATE_BATTLE_MAP returns FlutterMap widget', () async {
      final map = await h.eval('World.GENERATE_BATTLE_MAP()') as Map;
      expect(map['type'], 'FlutterMap');
      expect(map['props'], isNotNull);
    });

    test('GENERATE_BATTLE_MAP includes hero markers', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
      });
      await h.eval('Heroes.heroes := {"h1": __h}',
          boundValues: {'__h': hero});

      await h.eval('EXPECT("LENGTH(Heroes.heroes)", 1)');

      final map = await h.eval('World.GENERATE_BATTLE_MAP()') as Map;
      final children = map['props']['children'] as List;
      final markerLayer = children[1] as Map;
      final markers = markerLayer['props']['markers'] as List;
      expect(markers.length, greaterThanOrEqualTo(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Hero Detail tests
  // ═══════════════════════════════════════════════════════════════════
  group('HeroDetail', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();

      // Register alignment constants
      final cs = h.constantsSet;
      cs.registerConstant(0, cs.includeIdentifier('UNKNOWN'));
      cs.registerConstant(1, cs.includeIdentifier('NEUTRAL'));
      cs.registerConstant(2, cs.includeIdentifier('MOSTLYGOOD'));
      cs.registerConstant(3, cs.includeIdentifier('GOOD'));
      cs.registerConstant(4, cs.includeIdentifier('REASONABLE'));
      cs.registerConstant(5, cs.includeIdentifier('NOTQUITE'));
      cs.registerConstant(6, cs.includeIdentifier('BAD'));
      cs.registerConstant(7, cs.includeIdentifier('UGLY'));
      cs.registerConstant(8, cs.includeIdentifier('EVIL'));

      // Heroes stub with selected_hero
      await h.eval(r'''
        Heroes := OBJECT{
            heroes: {},
            selected_hero: null,
            total_heroes: 0,
            SET_SELECTED_HERO: (hero) => selected_hero := hero
        }
      ''');

      await h.eval(r'''
        _ALIGNMENT_LABELS := ['unknown', 'very_good', 'good', 'mostly_good', 'neutral', 'mostly_bad', 'bad', 'very_bad', 'evil', 'super_evil'];
        _detail_fields := [
            OBJECT{section: 'Biography', label: 'Full Name', accessor: (hero) => hero.FULL_NAME, display_type: 'text'},
            OBJECT{section: 'Biography', label: 'Alignment', accessor: (hero) => hero.ALIGNMENT, display_type: 'enum_label', enum_labels: _ALIGNMENT_LABELS}
        ]
      ''');

      h.runtime.setTernaryFunction('BIOGRAPHY',
          (ctx, caller, hero, accessor, defaultVal) => 4);
      h.runtime.setTernaryFunction('IMAGE',
          (ctx, caller, hero, accessor, defaultVal) => null);

      await h.loadFile('$_shqlDir/hero_detail.shql');
    });

    test('GENERATE_HERO_DETAIL returns SizedBox when no hero selected',
        () async {
      final result = await h.eval('Detail.GENERATE_HERO_DETAIL()') as Map;
      expect(result['type'], 'SizedBox');
    });

    test('GENERATE_HERO_DETAIL returns scrollable view with hero', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'full_name': 'Bruce Wayne',
        'alignment': 4,
      });
      await h.eval('Heroes.selected_hero := __h',
          boundValues: {'__h': hero});

      final result = await h.eval('Detail.GENERATE_HERO_DETAIL()') as Map;
      expect(result['type'], 'SingleChildScrollView');
    });

    test('__MAKE_DETAIL_CARD creates card with title', () async {
      final card = await h.eval(
              "Detail.__MAKE_DETAIL_CARD('Test Section', [{'type': 'Text', 'props': {'data': 'Hello'}}])")
          as Map;
      expect(card['type'], 'Padding');
    });

    test('__MAKE_ROW creates label-value row', () async {
      final rows =
          await h.eval("Detail.__MAKE_ROW('Name', 'Batman')") as List;
      expect(rows.length, 2); // Row + SizedBox
      final row = rows[0] as Map;
      expect(row['type'], 'Row');
    });

    test('__LAYOUT_STAT_ROWS groups stats in rows of 3', () async {
      await h.eval(r'''
        __test_stats := [
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "1"}}},
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "2"}}},
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "3"}}},
            {"type": "Expanded", "child": {"type": "Text", "props": {"data": "4"}}}
        ]
      ''');
      final rows =
          await h.eval('Detail.__LAYOUT_STAT_ROWS(__test_stats)') as List;
      final rowWidgets = rows.where((e) => (e as Map)['type'] == 'Row');
      expect(rowWidgets.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Hero Cards tests
  // ═══════════════════════════════════════════════════════════════════
  group('HeroCards', () {
    late ShqlTestRunner h;

    setUp(() async {
      h = await _standardSetUp();

      await h.eval('Prefs := OBJECT{is_dark_mode: FALSE}');

      await h.eval(r'''
        Heroes := OBJECT{
            heroes: {},
            selected_hero: null,
            total_heroes: 0,
            SELECT_HERO: (hero) => selected_hero := hero
        }
      ''');

      await h.eval(r'''
        Filters := OBJECT{
            displayed_heroes: [],
            active_filter_index: -1,
            current_query: ''
        }
      ''');

      await h.eval(r'''
        _ALIGNMENT_LABELS := ['unknown', 'very_good', 'good', 'mostly_good', 'neutral', 'mostly_bad', 'bad', 'very_bad', 'evil', 'super_evil'];
        _summary_fields := [
            OBJECT{prop_name: 'name', accessor: (hero) => hero.NAME, is_stat: FALSE},
            OBJECT{prop_name: 'alignment', accessor: (hero) => hero.ALIGNMENT, is_stat: FALSE},
            OBJECT{prop_name: 'url', accessor: (hero) => hero.URL, is_stat: FALSE}
        ]
      ''');

      await h.loadFile('$_shqlDir/hero_cards.shql');
    });

    test('__HERO_SUBTITLE joins publisher and race', () async {
      await h.eval(r'''
        EXPECT("Cards.__HERO_SUBTITLE('DC', 'Human')", 'DC • Human');
        EXPECT("Cards.__HERO_SUBTITLE('DC', '')", 'DC');
        EXPECT("Cards.__HERO_SUBTITLE('', 'Human')", 'Human');
        EXPECT("Cards.__HERO_SUBTITLE('', '')", '');
        EXPECT("Cards.__HERO_SUBTITLE(null, null)", '')
      ''');
    });

    test('__ALIGN_IDX clamps to valid range', () async {
      await h.eval(r'''
        EXPECT("Cards.__ALIGN_IDX(0)", 0);
        EXPECT("Cards.__ALIGN_IDX(5)", 5);
        EXPECT("Cards.__ALIGN_IDX(-1)", 0);
        EXPECT("Cards.__ALIGN_IDX(99)", 0)
      ''');
    });

    test('GENERATE_HERO_CARDS returns empty for empty list', () async {
      final result = await h.eval(
              "Cards.GENERATE_HERO_CARDS([], '_heroes', TRUE)")
          as List;
      expect(result, isEmpty);
    });

    test('GENERATE_HERO_CARDS generates cards for heroes', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
        'url': null,
        'locked': false,
      });

      final cards = await h.eval(
          "Cards.GENERATE_HERO_CARDS([__h], '_heroes', TRUE)",
          boundValues: {'__h': hero}) as List;
      expect(cards.length, 1);

      final card = cards[0] as Map;
      expect(card['type'], 'DismissibleCard');
    });

    test('GENERATE_HERO_CARDS without delete wraps in HeroCardBody',
        () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
        'url': null,
        'locked': false,
      });

      final cards = await h.eval(
          "Cards.GENERATE_HERO_CARDS([__h], '_search', FALSE)",
          boundValues: {'__h': hero}) as List;
      final card = cards[0] as Map;
      expect(card['type'], 'HeroCardBody');
    });

    test('GENERATE_SAVED_HEROES_CARDS returns empty state when no heroes',
        () async {
      final result =
          await h.eval('Cards.GENERATE_SAVED_HEROES_CARDS()') as List;
      expect(result.length, 1);
      final card = result[0] as Map;
      expect(card['type'], 'Center');
    });

    test('CACHE_HERO_CARD stores card in cache', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
        'url': null,
        'locked': false,
      });
      await h.eval('Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero});
      expect(await h.eval("Cards.card_cache['h1']"), isNotNull);
    });

    test('REMOVE_CACHED_CARD removes from cache', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
        'url': null,
        'locked': false,
      });
      await h.eval('Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero});
      await h.eval(r'''
        Cards.REMOVE_CACHED_CARD('h1');
        ASSERT("Cards.card_cache['h1'] = null")
      ''');
    });

    test('CLEAR_CARD_CACHE empties entire cache', () async {
      final hero = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
        'url': null,
        'locked': false,
      });
      await h.eval('Cards.CACHE_HERO_CARD(__h)',
          boundValues: {'__h': hero});
      await h.eval(r'''
        Cards.CLEAR_CARD_CACHE();
        EXPECT("LENGTH(Cards.card_cache)", 0)
      ''');
    });

    test('CACHE_HERO_CARDS batch-caches multiple heroes', () async {
      final h1 = h.makeObject({
        'id': 'h1',
        'name': 'Batman',
        'alignment': 3,
        'url': null,
        'locked': false,
      });
      final h2 = h.makeObject({
        'id': 'h2',
        'name': 'Superman',
        'alignment': 2,
        'url': null,
        'locked': false,
      });
      await h.eval(r'''
        Cards.CACHE_HERO_CARDS([__h1, __h2]);
        EXPECT("LENGTH(Cards.card_cache)", 2)
      ''', boundValues: {'__h1': h1, '__h2': h2});
    });

    test('__HERO_SEMANTICS builds accessibility label', () async {
      final stats = <dynamic>[
        h.makeObject({'label': 'STR', 'value': 80}),
        h.makeObject({'label': 'INT', 'value': 90}),
      ];
      final result = await h.eval(
          "Cards.__HERO_SEMANTICS('Batman', 'good', __stats)",
          boundValues: {'__stats': stats});
      expect(result, contains('Batman'));
      expect(result, contains('good'));
      expect(result, contains('STR'));
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
      final rows = await h.eval(
          'Cards.__MAKE_STAT_CHIP_ROWS(__stats)',
          boundValues: {'__stats': stats}) as List;
      expect(rows, isNotEmpty);
      final row = rows.firstWhere((e) => (e as Map)['type'] == 'Row') as Map;
      expect(row['children'], isNotEmpty);
    });
  });
}
