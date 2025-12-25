import 'package:hero_common/models/hero_model.dart';

abstract interface class HeroRepositing {
  void persist(HeroModel hero);

  void delete(HeroModel hero);

  void clear();

  // TODO: can I make a proper dispose pattern here?
  Future<Null> dispose();

  List<HeroModel> get heroes;

  Map<String, HeroModel> get heroesById;
}
