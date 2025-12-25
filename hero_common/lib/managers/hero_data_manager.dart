import 'package:shql/execution/runtime/runtime.dart' show Runtime;
import 'package:shql/parser/constants_set.dart';
import 'package:hero_common/managers/hero_data_managing.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/persistence/hero_repositing.dart';
import 'package:hero_common/predicates/hero_predicate.dart';

class HeroDataManager implements HeroDataManaging {
  final Runtime _runtime;
  final ConstantsSet _constantsSet;

  HeroDataManager(
    HeroRepositing repository, {
    required Runtime runtime,
    required ConstantsSet constantsSet,
  }) : _repository = repository,
       _runtime = runtime,
       _constantsSet = constantsSet,
       _heroesByExternalId = repository.heroes.asMap().map(
         (key, value) => MapEntry(value.externalId, value),
       );

  @override
  void persist(HeroModel hero, {void Function(HeroModel)? action}) {
    _heroesByExternalId[hero.externalId] = hero;
    _repository.persist(hero);
    if (action != null) {
      action(hero);
    }
  }

  @override
  void delete(HeroModel hero) {
    _heroesByExternalId.remove(hero.externalId);
    _repository.delete(hero);
  }

  @override
  void clear() {
    _heroesByExternalId.clear();
    _repository.clear();
  }

  @override
  Future<List<HeroModel>> query(String query, {bool Function(HeroModel)? filter}) async {
    if (query.trim().isEmpty) {
      var allHeroes = _heroesByExternalId.values.toList();
      allHeroes.sort();
      return allHeroes;
    }
    var predicate = HeroPredicate(query, runtime: _runtime, constantsSet: _constantsSet);
    var result = <HeroModel>[];
    for (var hero in _heroesByExternalId.values) {
      if (await predicate.evaluate(hero) &&
          (filter == null || filter(hero))) {
        result.add(hero);
      }
    }

    result.sort();
    return result;
  }

  @override
  HeroModel? getByExternalId(String externalId) {
    return _heroesByExternalId[externalId];
  }

  @override
  HeroModel? getById(String id) {
    return _repository.heroesById[id];
  }

  @override
  Future<Null> dispose() async {
    await _repository.dispose();
  }

  @override
  List<HeroModel> get heroes {
    var snapshot = _repository.heroes;
    snapshot.sort();
    return snapshot;
  }

  @override
  Future<HeroModel> heroFromJson(Map<String, dynamic> json, DateTime timestamp) async {
    var externalId = json['id'] as String;
    var currentVersion = getByExternalId(externalId);
    if (currentVersion != null) {
      return currentVersion.apply(json, timestamp, false);
    }
    return HeroModel.fromJson(json, timestamp);
  }

  final Map<String, HeroModel> _heroesByExternalId;

  final HeroRepositing _repository;
}
