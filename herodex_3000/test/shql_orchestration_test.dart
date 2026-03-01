import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';

/// Lightweight SHQL stubs for dependencies that record calls.
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

/// Test harness for SHQL orchestration tests.
class ShqlTestHarness {
  late Runtime runtime;
  late ConstantsSet constantsSet;
  final List<String> callLog = [];

  Future<void> setUp() async {
    constantsSet = Runtime.prepareConstantsSet();
    runtime = Runtime.prepareRuntime(constantsSet);

    // Load stdlib
    final stdlibCode =
        await File('../shql/assets/stdlib.shql').readAsString();
    await _exec(stdlibCode);

    // Wire up runtime callbacks needed by SHQL builtins
    runtime.saveStateFunction = (key, value) async {};
    runtime.loadStateFunction = (key, defaultValue) async => defaultValue;
    runtime.navigateFunction = (route) async {};
    runtime.notifyListeners = (name) {};
    runtime.debugLogFunction = (msg) {};

    // Load stubs
    await _exec(_stubs);
  }

  Future<dynamic> _exec(String code, {Map<String, dynamic>? boundValues}) {
    return Engine.execute(
      code,
      runtime: runtime,
      constantsSet: constantsSet,
      boundValues: boundValues,
    );
  }

  Future<dynamic> eval(String expr, {Map<String, dynamic>? boundValues}) =>
      _exec(expr, boundValues: boundValues);

  Future<void> loadFile(String path) async {
    final code = await File(path).readAsString();
    await _exec(code);
  }

  /// Register a mock Dart callback that logs its invocation.
  void mockUnary(String name, [dynamic Function(dynamic)? impl]) {
    runtime.setUnaryFunction(name, (ctx, caller, arg) {
      callLog.add('$name(${_describe(arg)})');
      return impl?.call(arg);
    });
  }

  void mockBinary(String name,
      [dynamic Function(dynamic, dynamic)? impl]) {
    runtime.setBinaryFunction(name, (ctx, caller, a, b) {
      callLog.add('$name(${_describe(a)}, ${_describe(b)})');
      return impl?.call(a, b);
    });
  }

  void mockTernary(String name,
      [dynamic Function(dynamic, dynamic, dynamic)? impl]) {
    runtime.setTernaryFunction(name, (ctx, caller, a, b, c) {
      callLog.add('$name(${_describe(a)}, ${_describe(b)}, ${_describe(c)})');
      return impl?.call(a, b, c);
    });
  }

  /// Create a SHQL Object from a Dart map.
  Object makeObject(Map<String, dynamic> map) {
    final obj = Object();
    for (final entry in map.entries) {
      final id =
          constantsSet.identifiers.include(entry.key.toUpperCase());
      obj.setVariable(id, entry.value);
    }
    return obj;
  }

  /// Read a field from a SHQL Object.
  dynamic readField(dynamic obj, String field) {
    if (obj is! Object) return null;
    final id = constantsSet.identifiers.include(field.toUpperCase());
    final member = obj.resolveIdentifier(id);
    if (member is Variable) return member.value;
    return member;
  }

  /// Describe a value for call log (extract ID/NAME from Objects).
  static String _describe(dynamic value) {
    if (value is Object) {
      // Try to find an ID or NAME field
      for (final entry in value.variables.entries) {
        if (entry.value.value is String) return entry.value.value as String;
      }
      return '<object>';
    }
    return '$value';
  }
}

// ─── Shared paths ───────────────────────────────────────────────────
const _shqlDir = 'assets/shql';

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // Heroes.shql tests
  // ═══════════════════════════════════════════════════════════════════
  group('Heroes', () {
    late ShqlTestHarness h;

    setUp(() async {
      h = ShqlTestHarness();
      await h.setUp();
      h.mockUnary('_HERO_DATA_DELETE');
      h.mockUnary('_HERO_DATA_TOGGLE_LOCK', (id) {
        return h.makeObject({'locked': true});
      });
      h.mockUnary('_SHOW_SNACKBAR');

      await h.loadFile('$_shqlDir/heroes.shql');
    });

    test('ON_HERO_ADDED adds hero to map and updates total', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': hero});

      expect(await h.eval('Heroes.total_heroes'), 1);
      expect(await h.eval('Heroes.heroes["h1"].NAME'), 'Batman');
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

      expect(await h.eval('Heroes.total_heroes'), 0);
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
      await h.eval("Heroes.DELETE_HERO('h1')");

      expect(await h.eval('Heroes.total_heroes'), 0);
      expect(await h.eval('Heroes.heroes["h1"]'), isNull);
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

      await h.eval('Heroes.PERSIST_AND_REBUILD(__h)',
          boundValues: {'__h': hero});

      expect(await h.eval('Heroes.total_heroes'), 1);
      expect(await h.eval('Heroes.heroes["h1"].NAME'), 'Batman');

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
      await h.eval('Heroes.PERSIST_AND_REBUILD(__h)',
          boundValues: {'__h': newHero});

      expect(await h.eval('Heroes.total_heroes'), 1);
      expect(
          await h.eval('Heroes.heroes["h1"].NAME'), 'Batman (Updated)');

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
      await h.eval("Heroes.TOGGLE_LOCK('h1')");

      expect(h.callLog.first, '_HERO_DATA_TOGGLE_LOCK(h1)');
      expect(await h.eval('Heroes.heroes["h1"].LOCKED'), true);
    });

    test('ON_HERO_CLEAR resets everything', () async {
      final h1 = h.makeObject({'id': 'h1', 'name': 'Batman'});
      final h2 = h.makeObject({'id': 'h2', 'name': 'Superman'});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': h1});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': h2});

      await h.eval('Heroes.ON_HERO_CLEAR()');

      expect(await h.eval('Heroes.total_heroes'), 0);
      expect(await h.eval('LENGTH(Heroes.heroes)'), 0);
      expect(await h.eval('Stats.log'), contains('clear'));
      expect(await h.eval('Filters.log'), contains('clear'));
      expect(await h.eval('Cards.log'), contains('clear'));
    });

    test('CLEAR_SELECTED_IF clears selected when ID matches', () async {
      final hero = h.makeObject({'id': 'h1', 'name': 'Batman'});
      await h.eval('Heroes.SET_SELECTED_HERO(__h)',
          boundValues: {'__h': hero});
      expect(await h.eval('Heroes.selected_hero'), isNotNull);

      await h.eval("Heroes.CLEAR_SELECTED_IF('h1')");
      expect(await h.eval('Heroes.selected_hero'), isNull);
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
      await h.eval('Heroes.SELECT_HERO(__h)',
          boundValues: {'__h': hero});

      expect(await h.eval('Heroes.selected_hero.NAME'), 'Batman');
      expect(await h.eval('Nav.current'), 'hero_detail');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Reconciliation stack discipline tests
  // ═══════════════════════════════════════════════════════════════════
  group('Reconciliation', () {
    late ShqlTestHarness h;

    setUp(() async {
      h = ShqlTestHarness();
      await h.setUp();
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

      await h.eval(
        "Heroes.RECONCILE_UPDATE(__old, __opaque, 'Updated', 'Batman: updated')",
        boundValues: {'__old': oldHero, '__opaque': opaqueModel},
      );

      expect(await h.eval('Heroes.total_heroes'), 1);
      expect(await h.eval('Heroes.heroes["h1"].NAME'), 'Batman v2');

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

      await h.eval(
        "Heroes.RECONCILE_DELETE(__hero, 'Deleted', 'Batman: deleted')",
        boundValues: {'__hero': hero},
      );

      expect(await h.eval('Heroes.total_heroes'), 0);
      expect(await h.eval('Heroes.heroes["h1"]'), isNull);
      expect(await h.eval('Cards.log'), contains('remove:h1'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Search flow tests
  // ═══════════════════════════════════════════════════════════════════
  group('Search', () {
    late ShqlTestHarness h;

    setUp(() async {
      h = ShqlTestHarness();
      await h.setUp();
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

      await h.eval("Search.SEARCH_HEROES('a')");

      expect(fetchCalled, false);
      expect(await h.eval('LENGTH(Search.search_results)'), 0);
    });

    test('SEARCH_HEROES with all already-saved heroes', () async {
      final batman =
          h.makeObject({'id': 'h1', 'name': 'Batman', 'locked': false});
      await h.eval('Heroes.ON_HERO_ADDED(__h)',
          boundValues: {'__h': batman});

      // _FETCH_HEROES returns an opaque model inside an Object
      // The model itself is opaque to SHQL — just a Dart value
      final model1 = 'opaque-batman';

      h.runtime.setUnaryFunction('_FETCH_HEROES', (ctx, caller, query) {
        final result = h.makeObject({'success': true});
        // Set RESULTS as a list containing the opaque model
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

      h.runtime.setUnaryFunction('_SAVE_HERO', (ctx, caller, model) {
        h.callLog.add('_SAVE_HERO');
        return savedHero;
      });

      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) {
        h.callLog.add('_REVIEW_HERO');
        return 'save';
      });

      h.callLog.clear();
      await h.eval("Search.SEARCH_HEROES('batman')");

      expect(h.callLog, contains('_SAVE_HERO'));
      expect(await h.eval('Heroes.heroes["h1"].NAME'), 'Batman');
      expect(await h.eval('Heroes.total_heroes'), 1);
      expect(await h.eval('LENGTH(Search.search_results)'), 1);
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

      h.runtime.setUnaryFunction('_MAP_HERO', (ctx, caller, model) {
        h.callLog.add('_MAP_HERO');
        return mappedHero;
      });

      h.runtime.setTernaryFunction(
          '_REVIEW_HERO', (ctx, caller, model, current, total) => 'skip');

      h.callLog.clear();
      await h.eval("Search.SEARCH_HEROES('batman')");

      expect(saveCalled, false, reason: 'Skipped heroes should not be saved');
      expect(h.callLog, contains('_MAP_HERO'));
      expect(await h.eval('Heroes.heroes["h1"]'), isNull);
      expect(await h.eval('LENGTH(Search.search_results)'), 1);
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

      await h.eval("Search.SEARCH_HEROES('heroes')");

      expect(reviewCount, 1,
          reason: 'saveAll should skip review for remaining');
      expect(saveCount, 2, reason: 'Both heroes should be saved');
      expect(await h.eval('Heroes.total_heroes'), 2);
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

      await h.eval("Search.SEARCH_HEROES('heroes')");

      expect(mapCount, 2, reason: 'All remaining should be mapped on cancel');
      expect(await h.eval('Heroes.total_heroes'), 0,
          reason: 'No heroes saved on cancel');
      expect(await h.eval('LENGTH(Search.search_results)'), 2);
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

      await h.eval("Search.SEARCH_HEROES('batman')");
      await h.eval("Search.SEARCH_HEROES('superman')");

      final history = await h.eval('Search.search_history') as List;
      expect(history, hasLength(2));
      expect(history[0], 'superman');
      expect(history[1], 'batman');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // HeroEdit stack discipline tests
  // ═══════════════════════════════════════════════════════════════════
  group('HeroEdit', () {
    late ShqlTestHarness h;

    setUp(() async {
      h = ShqlTestHarness();
      await h.setUp();
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
      expect(await h.eval('Heroes.heroes["h1"].NAME'),
          'Batman (Amended)');
      expect(await h.eval('Heroes.total_heroes'), 1);

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
}
