import 'package:flutter_test/flutter_test.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:herodex_3000/core/hero_schema.dart';
import 'package:shql/testing/shql_test_runner.dart';

const _stdlibPath = '../shql/assets/stdlib.shql';
const _testLibPath = '../shql/assets/shql_test.shql';
const _shqlDir = 'assets/shql';

void main() {
  test('FULL_NAME accessible in hero_cards context', () async {
    final h = ShqlTestRunner.withExpect(expect);
    await h.setUp(stdlibPath: _stdlibPath, testLibPath: _testLibPath);
    HeroShqlAdapter.registerHeroSchema(h.constantsSet);
    
    // Print identifier count before schema
    var count = 0;
    try { h.constantsSet.identifiers.include('FULL_NAME'); count++; } catch (e) { /* */ }
    // ignore: avoid_print
    print('FULL_NAME before schema: registered');
    
    await h.test(HeroSchema.generateSchemaScript());
    // ignore: avoid_print
    print('Schema script loaded successfully');

    // Register no-op callbacks
    h.runtime.setUnaryFunction('FETCH', (ctx, c, a) => null);
    h.runtime.setUnaryFunction('_SHOW_SNACKBAR', (ctx, c, a) => null);
    h.runtime.setBinaryFunction('POST', (ctx, c, a, b) => <String, dynamic>{'status': 0});
    h.runtime.setBinaryFunction('_ON_PREF_CHANGED', (ctx, c, a, b) => null);
    h.runtime.setBinaryFunction('_PROMPT', (ctx, c, a, b) => null);
    h.runtime.setBinaryFunction('FETCH_AUTH', (ctx, c, a, b) => null);
    h.runtime.setTernaryFunction('PATCH_AUTH', (ctx, c, a, b, d) => <String, dynamic>{'status': 200});
    h.runtime.setTernaryFunction('_EVAL_PREDICATE', (ctx, c, a, b, d) => true);
    h.runtime.setNullaryFunction('__ON_AUTHENTICATED', (ctx, c) => null);
    h.runtime.setNullaryFunction('_HERO_DATA_CLEAR', (ctx, c) => null);
    h.runtime.setNullaryFunction('_SIGN_OUT', (ctx, c) => null);
    h.runtime.setNullaryFunction('_COMPILE_FILTERS', (ctx, c) => null);
    h.runtime.setNullaryFunction('_INIT_RECONCILE', (ctx, c) => null);
    h.runtime.setNullaryFunction('_FINISH_RECONCILE', (ctx, c) => null);
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
    h.runtime.setUnaryFunction('NUMBER', (ctx, c, a) {
      if (a is int) return a;
      if (a is String) return int.tryParse(a) ?? double.tryParse(a) ?? 0;
      if (a is double) return a;
      return a;
    });
    h.runtime.setBinaryFunction('MATCH', (ctx, c, a, b) => false);
    h.runtime.setBinaryFunction('_HERO_DATA_AMEND', (ctx, c, a, b) => null);
    h.runtime.setTernaryFunction('_REVIEW_HERO', (ctx, c, a, b, d) => null);
    
    // ignore: avoid_print
    print('Loading all shql files...');
    const files = ['auth', 'navigation', 'firestore', 'preferences', 'statistics', 'filters', 'heroes', 'hero_detail', 'hero_cards', 'search', 'hero_edit', 'world'];
    for (final name in files) {
      await h.loadFile('$_shqlDir/$name.shql');
      // ignore: avoid_print
      print('  Loaded $name.shql');
    }
    
    // Hero must include all nested fields that _summary_fields accessors reference
    final bio = h.makeObject({
      'full_name': 'Bruce Wayne', 'publisher': 'DC Comics', 'alignment': 3,
    });
    final stats = h.makeObject({
      'intelligence': 80, 'strength': 70, 'speed': 60,
      'durability': 50, 'power': 40, 'combat': 90,
    });
    final appearance = h.makeObject({'race': 'Human'});
    final image = h.makeObject({'url': null});
    final hero = h.makeObject({
      'id': 'h1', 'name': 'Batman', 'biography': bio,
      'powerstats': stats, 'appearance': appearance, 'image': image,
      'locked': false,
    });
    
    await h.test(r'''
      Cards.CACHE_HERO_CARD(__h);
      ASSERT(Cards.card_cache['h1'] <> null)
    ''', boundValues: {'__h': hero});
    // ignore: avoid_print
    print('CACHE_HERO_CARD succeeded!');
  });
}
