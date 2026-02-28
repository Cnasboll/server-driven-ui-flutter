import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/models/search_response_model.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/value_types/weight.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

import '../../widgets/conflict_resolver_dialog.dart';
import '../../persistence/shql_hero_data_manager.dart';
import '../hero_coordinator.dart';

/// Manages online hero search, API response caching, and the save-review flow.
///
/// This is separate from [HeroCoordinator] because search is a transient
/// workflow with its own state (_searchCache, _searchResults) that is not
/// part of the local hero data lifecycle.
class HeroSearchService {
  HeroSearchService({
    required ShqlBindings shqlBindings,
    required ShqlHeroDataManager heroDataManager,
    required HeroCoordinator coordinator,
    required GlobalKey<NavigatorState> navigatorKey,
    required VoidCallback onStateChanged,
  })  : _shqlBindings = shqlBindings,
        _heroDataManager = heroDataManager,
        _coordinator = coordinator,
        _navigatorKey = navigatorKey,
        _onStateChanged = onStateChanged;

  final ShqlBindings _shqlBindings;
  final ShqlHeroDataManager _heroDataManager;
  final HeroCoordinator _coordinator;
  final GlobalKey<NavigatorState> _navigatorKey;
  final VoidCallback _onStateChanged;

  /// API response cache — same query on the same day returns cached JSON.
  final Map<String, Map<String, dynamic>> _searchCache = {};

  /// Transient API search results keyed by externalId.
  final Map<String, HeroModel> _searchResults = {};

  String _cacheKey(String query) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '${query.toLowerCase()}|$today';
  }

  /// Get a search result by externalId (for SHQL™ _PERSIST_HERO callback).
  HeroModel? getSearchResult(String externalId) => _searchResults[externalId];

  Future<void> clearSearchResults() async {
    _searchResults.clear();
    await _shqlBindings.eval('Search.SET_SEARCH_STATE(__r, null, null)',
        boundValues: {'__r': <dynamic>[]});
  }

  // ---------------------------------------------------------------------------
  // Search flow
  // ---------------------------------------------------------------------------

  Future<void> search(String query) async {
    try {
      final heroService = await _coordinator.getHeroService();
      if (heroService == null) {
        await _shqlBindings.eval('Search.SET_SEARCH_STATE(__r, FALSE, null)',
            boundValues: {'__r': <dynamic>[]});
        _onStateChanged();
        return;
      }

      final key = _cacheKey(query);
      var data = _searchCache[key];
      if (data == null) {
        data = await heroService.search(query);
        if (data != null && data['response'] == 'success') {
          _searchCache[key] = data;
        }
      }
      if (data == null || data['response'] != 'success') {
        await _shqlBindings.eval('Search.SET_SEARCH_STATE(__r, FALSE, __s)',
            boundValues: {
              '__r': <dynamic>[],
              '__s': data?['error']?.toString() ?? 'No results found for "$query"',
            });
        _onStateChanged();
        return;
      }

      // Set up conflict resolvers for weight/height ambiguity (like v04)
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

        _searchResults.clear();
        for (final hero in searchResponse.results) {
          _searchResults[hero.externalId] = hero;
        }
        await publishSearchResults(loading: false);
        _onStateChanged();
        // SHQL™ SAVE_SEARCH_HEROES() handles the save dialog loop after _FETCH_HEROES returns.
      } finally {
        Height.conflictResolver = previousHeightResolver;
        Weight.conflictResolver = previousWeightResolver;
      }
    } catch (e) {
      debugPrint('Search error: $e');
      await _shqlBindings.eval('Search.SET_SEARCH_STATE(__r, FALSE, __s)',
          boundValues: {'__r': <dynamic>[], '__s': 'Search failed: $e'});
      _onStateChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Save hero from search results
  // ---------------------------------------------------------------------------

  Future<void> saveHero(String externalId) async {
    final heroModel = _searchResults[externalId];
    if (heroModel == null) {
      debugPrint('Hero model not found for externalId: $externalId');
      return;
    }

    await _coordinator.persistHero(heroModel);
    await publishSearchResults();

    // Update selected hero if it matches — reuse the instance from Heroes.heroes.
    try {
      await _shqlBindings.eval('Heroes.REFRESH_SELECTED_IF(__eid)',
          boundValues: {'__eid': externalId});
    } catch (_) {}

    _onStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Publish search results to SHQL™
  // ---------------------------------------------------------------------------

  Future<void> publishSearchResults({bool? loading}) async {
    if (_searchResults.isEmpty) {
      await _shqlBindings.eval('Search.SET_SEARCH_STATE(__r, __l, null)',
          boundValues: {'__r': <dynamic>[], '__l': loading});
      return;
    }
    final objects = <dynamic>[];
    for (final entry in _searchResults.entries) {
      final saved = _heroDataManager.getByExternalId(entry.key);
      if (saved != null) {
        objects.add(HeroShqlAdapter.heroToDisplayObject(
          saved, _shqlBindings.identifiers, isSaved: true,
        ));
        _searchResults[entry.key] = saved;
      } else {
        objects.add(HeroShqlAdapter.heroToDisplayObject(
          entry.value, _shqlBindings.identifiers, isSaved: false,
        ));
      }
    }
    await _shqlBindings.eval('Search.SET_SEARCH_STATE(__r, __l, null)',
        boundValues: {'__r': objects, '__l': loading});
  }

  // ---------------------------------------------------------------------------
  // Hero review dialog (called from SHQL™ _REVIEW_HERO callback)
  // ---------------------------------------------------------------------------

  /// Shows a review dialog for a search result hero. Takes a SHQL™ hero object,
  /// looks up the HeroModel by externalId, and returns an action string
  /// ('save', 'skip', 'saveAll', 'cancel').
  Future<String> reviewHero(dynamic heroObj, int current, int total) async {
    final map = _shqlBindings.objectToMap(heroObj);
    final externalId = map['external_id']?.toString() ?? '';
    final hero = _searchResults[externalId];
    if (hero == null) return 'skip';
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
