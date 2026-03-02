import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/persistence/hero_repositing.dart';

class MockHeroRepository implements HeroRepositing {
  @override
  void persist(HeroModel hero) {
    _cache[hero.id] = hero;
  }

  @override
  void delete(HeroModel hero) {
    _cache.remove(hero.id);
  }

  @override
  void clear() {
    _cache.clear();
  }

  @override
  Future<Null> dispose() async {
    return null;
  }

  final Map<String, HeroModel> _cache = {};

  @override
  List<HeroModel> get heroes {
    var snapshot = _cache.values.toList();
    return snapshot;
  }

  @override
  Map<String, HeroModel> get heroesById => Map.unmodifiable(_cache);
}
