import 'package:hero_common/models/hero_model.dart';

abstract interface class HeroDataManaging {  
  void persist(HeroModel hero, {void Function(HeroModel)? action});
  void delete(HeroModel hero);
  void clear();
  Future<List<HeroModel>> query(String query, {bool Function(HeroModel)? filter});
  Future<Null> dispose(); 
  List<HeroModel> get heroes;
  HeroModel? getByExternalId(String externalId);
  HeroModel? getById(String id);
  /// Parses a HeroModel from JSON, using existing data if available,
  /// does not persists
  Future<HeroModel> heroFromJson(Map<String, dynamic> json, DateTime timestamp);
}
