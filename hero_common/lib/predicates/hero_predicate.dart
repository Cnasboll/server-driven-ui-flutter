import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart' show Runtime;
import 'package:shql/parser/constants_set.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';

class HeroPredicate {
  final String query;
  final Runtime _runtime;
  final ConstantsSet _constantsSet;

  HeroPredicate(this.query, {required Runtime runtime, required ConstantsSet constantsSet})
      : _runtime = runtime,
        _constantsSet = constantsSet;

  Future<bool> evaluate(HeroModel hero) async {
    if (query.isEmpty) {
      return hero.matches(query);
    }

    try {
      var sandbox = _runtime.sandbox();
      var boundValues = HeroShqlAdapter.heroToBoundValues(hero, sandbox.identifiers);

      var result = await Engine.execute(
        query,
        runtime: sandbox,
        constantsSet: _constantsSet,
        boundValues: boundValues,
      );

      if (result is bool) return result;
      return result != null && result != 0 && result != false;
    } catch (e) {
      return hero.matches(query);
    }
  }

  Future<List<HeroModel>> filter(List<HeroModel> heroes) async {
    var results = <HeroModel>[];
    for (var hero in heroes) {
      if (await evaluate(hero)) {
        results.add(hero);
      }
    }
    return results;
  }
}
