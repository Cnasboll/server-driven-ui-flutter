import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/models/search_response_model.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/value_types/weight.dart';
import 'package:http/http.dart' as http;
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

  void clearSearchResults() {
    _searchResults.clear();
    _setAndNotify('_search_results', []);
  }

  // ---------------------------------------------------------------------------
  // Search flow
  // ---------------------------------------------------------------------------

  Future<void> search(String query) async {
    try {
      final heroService = await _coordinator.getHeroService();
      if (heroService == null) {
        _setAndNotify('_search_results', []);
        _setAndNotify('_is_loading', false);
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
        _setAndNotify('_search_results', []);
        _setAndNotify('_is_loading', false);
        _setAndNotify('_search_summary',
            data?['error']?.toString() ?? 'No results found for "$query"');
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
        publishSearchResults();

        _setAndNotify('_is_loading', false);
        _onStateChanged();

        // Dialog-based one-by-one save flow (like v04's saveHeroes)
        await _showSaveHeroesDialog();
      } finally {
        Height.conflictResolver = previousHeightResolver;
        Weight.conflictResolver = previousWeightResolver;
      }
    } catch (e) {
      debugPrint('Search error: $e');
      _setAndNotify('_search_results', []);
      _setAndNotify('_is_loading', false);
      _setAndNotify('_search_summary', 'Search failed: $e');
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
    publishSearchResults();

    // Update selected hero if it matches
    try {
      final selectedEid = await _shqlBindings.eval(
        'IF _selected_hero != null THEN _selected_hero.external_id ELSE null',
      );
      if (selectedEid == externalId) {
        final saved = _heroDataManager.getByExternalId(externalId);
        if (saved != null) {
          _setAndNotify('_selected_hero',
            HeroShqlAdapter.heroToDisplayObject(saved, _shqlBindings.identifiers, isSaved: true),
          );
        }
      }
    } catch (_) {}

    _onStateChanged();
  }

  // ---------------------------------------------------------------------------
  // Publish search results to SHQL™
  // ---------------------------------------------------------------------------

  void publishSearchResults() {
    if (_searchResults.isEmpty) {
      _setAndNotify('_search_results', []);
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
    _setAndNotify('_search_results', objects);
  }

  // ---------------------------------------------------------------------------
  // Save heroes dialog (one-by-one review)
  // ---------------------------------------------------------------------------

  Future<void> _showSaveHeroesDialog() async {
    final unsaved = [
      for (final entry in _searchResults.entries)
        if (_heroDataManager.getByExternalId(entry.key) == null) entry.value,
    ];
    final totalResults = _searchResults.length;
    final alreadySaved = totalResults - unsaved.length;

    if (unsaved.isEmpty) {
      _setAndNotify('_search_summary',
        '$totalResults result${totalResults == 1 ? '' : 's'} found, all already saved');
      _onStateChanged();
      return;
    }

    int saveCount = 0;
    int skipCount = 0;
    bool cancelled = false;

    for (int i = 0; i < unsaved.length; i++) {
      final hero = unsaved[i];
      final result = await _showHeroReviewDialog(hero, i + 1, unsaved.length);

      switch (result) {
        case ReviewAction.save:
          await _coordinator.persistHero(hero);
          saveCount++;
          break;
        case ReviewAction.skip:
          skipCount++;
          break;
        case ReviewAction.saveAll:
          await _coordinator.persistHero(hero);
          saveCount++;
          for (int j = i + 1; j < unsaved.length; j++) {
            await _coordinator.persistHero(unsaved[j]);
            saveCount++;
          }
          i = unsaved.length;
          break;
        case ReviewAction.cancel:
          skipCount += unsaved.length - i;
          cancelled = true;
          i = unsaved.length;
          break;
      }
    }

    final parts = <String>[];
    parts.add('$totalResults found');
    if (alreadySaved > 0) parts.add('$alreadySaved already saved');
    if (saveCount > 0) parts.add('$saveCount saved');
    if (skipCount > 0) parts.add('$skipCount skipped');
    if (cancelled) parts.add('cancelled');
    _setAndNotify('_search_summary', parts.join(', '));
    _onStateChanged();
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

  // ---------------------------------------------------------------------------
  // Generic HTTP fetch (for SHQL™ FETCH callback)
  // ---------------------------------------------------------------------------

  static Future<dynamic> httpFetch(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Fetch error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _setAndNotify(String name, dynamic value) {
    _shqlBindings.setVariable(name, value);
    _shqlBindings.notifyListeners(name);
  }
}
