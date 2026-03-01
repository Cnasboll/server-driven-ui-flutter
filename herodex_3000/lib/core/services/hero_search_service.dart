import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/models/search_response_model.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/value_types/weight.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

import '../../widgets/conflict_resolver_dialog.dart';
import 'package:hero_common/managers/hero_data_managing.dart';
import '../hero_coordinator.dart';

/// Dart platform primitives for the hero search workflow.
///
/// SHQL™ drives the loop. This class provides the callbacks SHQL calls:
/// - `_FETCH_HEROES(query)` → API fetch + parse → list of opaque HeroModels
/// - `_GET_SAVED_ID(model)` → returns internal ID if already saved, else null
/// - `_SAVE_HERO(model)` → persist to DB + create SHQL Object
/// - `_MAP_HERO(model)` → create SHQL Object without persisting
/// - `_REVIEW_HERO(model, current, total)` → show review dialog → action string
class HeroSearchService {
  HeroSearchService({
    required ShqlBindings shqlBindings,
    required HeroDataManaging heroDataManager,
    required HeroCoordinator coordinator,
    required GlobalKey<NavigatorState> navigatorKey,
  })  : _shqlBindings = shqlBindings,
        _heroDataManager = heroDataManager,
        _coordinator = coordinator,
        _navigatorKey = navigatorKey;

  final ShqlBindings _shqlBindings;
  final HeroDataManaging _heroDataManager;
  final HeroCoordinator _coordinator;
  final GlobalKey<NavigatorState> _navigatorKey;

  /// API response cache — same query on the same day returns cached JSON.
  final Map<String, Map<String, dynamic>> _searchCache = {};

  String _cacheKey(String query) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '${query.toLowerCase()}|$today';
  }

  void _pruneCache() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    _searchCache.removeWhere((key, _) => !key.endsWith(today));
  }

  // ---------------------------------------------------------------------------
  // _FETCH_HEROES: API fetch + parse → opaque HeroModel list
  // ---------------------------------------------------------------------------

  /// Returns {success, results: [HeroModel...], error}.
  /// HeroModels are opaque to SHQL — passed to other callbacks for inspection.
  Future<dynamic> fetchHeroes(String query) async {
    try {
      final heroService = await _coordinator.getHeroService();
      if (heroService == null) {
        return _errorResult('No API credentials configured');
      }

      _pruneCache();
      final key = _cacheKey(query);
      var data = _searchCache[key];
      if (data == null) {
        data = await heroService.search(query);
        if (data != null && data['response'] == 'success') {
          _searchCache[key] = data;
        }
      }
      if (data == null || data['response'] != 'success') {
        return _errorResult(
          data?['error']?.toString() ?? 'No results found for "$query"',
        );
      }

      final previousHeightResolver = Height.conflictResolver;
      final previousWeightResolver = Weight.conflictResolver;
      Height.conflictResolver = FlutterConflictResolver<Height>(
        (name, v, cv) => showConflictDialog(_navigatorKey, name, v, cv),
      );
      Weight.conflictResolver = FlutterConflictResolver<Weight>(
        (name, v, cv) => showConflictDialog(_navigatorKey, name, v, cv),
      );

      try {
        final failures = <String>[];
        final searchResponse = await SearchResponseModel.fromJson(
          _heroDataManager, data, DateTime.timestamp(), failures,
        );
        for (final f in failures) {
          debugPrint('Search parse failure: $f');
        }

        return _shqlBindings.mapToObject({
          'success': true,
          'results': searchResponse.results,
          'error': null,
        });
      } finally {
        Height.conflictResolver = previousHeightResolver;
        Weight.conflictResolver = previousWeightResolver;
      }
    } catch (e) {
      debugPrint('Search error: $e');
      return _errorResult('Search failed: $e');
    }
  }

  dynamic _errorResult(String message) => _shqlBindings.mapToObject({
    'success': false,
    'results': <dynamic>[],
    'error': message,
  });

  // ---------------------------------------------------------------------------
  // Callbacks operating on opaque HeroModels
  // ---------------------------------------------------------------------------

  /// Returns the internal ID if this hero is already saved, null otherwise.
  dynamic getSavedId(dynamic hero) {
    if (hero is! HeroModel) return null;
    return _heroDataManager.getByExternalId(hero.externalId)?.id;
  }

  /// Persist to DB and return SHQL Object.
  dynamic saveHero(dynamic hero) {
    if (hero is! HeroModel) return null;
    _heroDataManager.persist(hero);
    return HeroShqlAdapter.heroToShqlObject(hero, _shqlBindings.identifiers);
  }

  /// Create SHQL Object without persisting (for display of skipped heroes).
  dynamic mapHero(dynamic hero) {
    if (hero is! HeroModel) return null;
    return HeroShqlAdapter.heroToShqlObject(hero, _shqlBindings.identifiers);
  }

  // ---------------------------------------------------------------------------
  // Review dialog (platform boundary)
  // ---------------------------------------------------------------------------

  /// Shows review dialog for an opaque HeroModel. Returns action string.
  Future<String> reviewHero(dynamic hero, int current, int total) async {
    if (hero is! HeroModel) return 'skip';
    final action = await _showHeroReviewDialog(hero, current, total);
    return switch (action) {
      ReviewAction.save => 'save',
      ReviewAction.skip => 'skip',
      ReviewAction.saveAll => 'saveAll',
      ReviewAction.cancel => 'cancel',
    };
  }

  Future<ReviewAction> _showHeroReviewDialog(HeroModel hero, int current, int total) {
    final completer = Completer<ReviewAction>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final overlayContext = _navigatorKey.currentState?.overlay?.context;
      if (overlayContext == null) {
        completer.complete(ReviewAction.cancel);
        return;
      }

      final ps = hero.powerStats;
      final totalPower = (ps.intelligence?.value ?? 0) + (ps.strength?.value ?? 0)
          + (ps.speed?.value ?? 0) + (ps.durability?.value ?? 0)
          + (ps.power?.value ?? 0) + (ps.combat?.value ?? 0);

      try {
        final result = await showDialog<ReviewAction>(
          context: overlayContext,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('$current of $total'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hero.image.url != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      hero.image.url!,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, _) => const Icon(Icons.person, size: 80),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(hero.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Alignment: ${hero.biography.alignment.name}',
                  style: TextStyle(color: Colors.grey[600])),
                Text('Total Power: $totalPower',
                  style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ReviewAction.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ReviewAction.skip),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ReviewAction.saveAll),
                child: const Text('Save All'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(ReviewAction.save),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        completer.complete(result ?? ReviewAction.cancel);
      } catch (e) {
        debugPrint('Review dialog error: $e');
        completer.complete(ReviewAction.cancel);
      }
    });

    return completer.future;
  }

}
