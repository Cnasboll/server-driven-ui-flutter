import 'package:hero_common/managers/hero_data_managing.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

/// Decorator around [HeroDataManaging] that maintains a Dart-side cache of
/// SHQL™ hero objects (`_heroObjectsById`) for the coordinator to look up
/// old objects before replace operations.
///
/// All SHQL™ state management (heroes map, stats, filter membership) is
/// handled by SHQL™ functions (ON_HERO_ADDED, ON_HERO_REMOVED, etc.).
/// This class only manages the Dart cache and delegates to the inner
/// data manager.
class ShqlHeroDataManager implements HeroDataManaging {
  ShqlHeroDataManager(this._inner, this._shqlBindings);

  final HeroDataManaging _inner;
  final ShqlBindings _shqlBindings;

  /// heroId → SHQL™ Object. Dart-side cache for coordinator lookups.
  final Map<String, Object> _heroObjectsById = {};

  // ---------------------------------------------------------------------------
  // HeroDataManaging — delegation + cache sync
  // ---------------------------------------------------------------------------

  @override
  void persist(HeroModel hero, {void Function(HeroModel)? action}) {
    _inner.persist(hero, action: action);
    final obj = HeroShqlAdapter.heroToDisplayObject(
      hero, _shqlBindings.identifiers, isSaved: true,
    );
    _heroObjectsById[hero.id] = obj;
  }

  @override
  void delete(HeroModel hero) {
    _inner.delete(hero);
    _heroObjectsById.remove(hero.id);
  }

  @override
  void clear() {
    _inner.clear();
    _heroObjectsById.clear();
  }

  @override
  Future<Null> dispose() async {
    _heroObjectsById.clear();
    return _inner.dispose();
  }

  @override
  List<HeroModel> get heroes => _inner.heroes;

  @override
  HeroModel? getByExternalId(String externalId) =>
      _inner.getByExternalId(externalId);

  @override
  HeroModel? getById(String id) => _inner.getById(id);

  @override
  Future<List<HeroModel>> query(
    String query, {
    bool Function(HeroModel)? filter,
  }) => _inner.query(query, filter: filter);

  @override
  Future<HeroModel> heroFromJson(
    Map<String, dynamic> json,
    DateTime timestamp,
  ) => _inner.heroFromJson(json, timestamp);

  // ---------------------------------------------------------------------------
  // Public: hero object access
  // ---------------------------------------------------------------------------

  /// Read-only view of the hero SHQL™ Objects by id.
  Map<String, Object> get heroObjectsById =>
      Map<String, Object>.unmodifiable(_heroObjectsById);

  /// Get a single hero's SHQL™ Object by id.
  Object? getHeroObject(String heroId) => _heroObjectsById[heroId];

  // ---------------------------------------------------------------------------
  // Public: initialization
  // ---------------------------------------------------------------------------

  /// Build the Dart-side cache and call ON_HERO_ADDED per hero.
  /// ON_HERO_ADDED updates the SHQL™ `_heroes` map and running stats.
  /// During init, `_filtered_heroes` is `[]` so the filter loop inside
  /// ON_HERO_ADDED is skipped. Filters are built afterwards by the
  /// coordinator via REBUILD_ALL_FILTERS.
  Future<void> initialize() async {
    final allHeroes = _inner.heroes;
    _heroObjectsById.clear();
    final objects = HeroShqlAdapter.heroesToDisplayList(
      allHeroes, _shqlBindings.identifiers, isSaved: true,
    );
    for (int i = 0; i < allHeroes.length; i++) {
      _heroObjectsById[allHeroes[i].id] = objects[i];
    }
    // Batch all ON_HERO_ADDED calls into a single SHQL execution to avoid
    // 44 separate parse → ExecutionContext → tick-loop cycles.
    if (objects.isNotEmpty) {
      await _shqlBindings.eval(
        'IF LENGTH(__heroes_to_add) > 0 THEN '
        'FOR __i := 0 TO LENGTH(__heroes_to_add) - 1 DO '
        'ON_HERO_ADDED(__heroes_to_add[__i])',
        boundValues: {'__heroes_to_add': objects},
      );
    }
  }
}
