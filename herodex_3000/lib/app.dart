import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:server_driven_ui/server_driven_ui.dart';

import 'core/herodex_widget_registry.dart';
import 'core/hero_coordinator.dart';
import 'core/services/hero_search_service.dart';
import 'core/services/http_client.dart' as http_client;
import 'core/services/connectivity_service.dart';
import 'core/services/firebase_auth_service.dart';
import 'core/services/firebase_service.dart';
import 'core/services/location_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'widgets/conflict_resolver_dialog.dart' show ReviewAction;
import 'widgets/dialogs.dart' as dialogs;
import 'package:hero_common/callbacks.dart';
import 'package:hero_common/managers/hero_data_manager.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/persistence/hero_repository.dart';
import 'persistence/sqflite_database_adapter.dart';
import 'package:hero_common/managers/hero_data_managing.dart';
import 'persistence/filter_compiler.dart';
import 'core/hero_schema.dart';

class HeroDexApp extends StatefulWidget {
  final SharedPreferences prefs;
  final FirebaseAuthService authService;

  const HeroDexApp({super.key, required this.prefs, required this.authService});

  @override
  State<HeroDexApp> createState() => _HeroDexAppState();
}

class _HeroDexAppState extends State<HeroDexApp> {
  late ShqlBindings _shqlBindings;
  late YamlUiEngine _yamlEngine;
  late HeroDataManaging _heroDataManager;
  late HeroCoordinator _coordinator;
  late HeroSearchService _searchService;
  late GoRouter _router;
  ConnectivityService? _connectivityService;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  bool _initialized = false;
  bool _authenticated = false;
  bool _loginReady = false;
  ParseTree? _predCallTree;
  String _loadingStatus = '';

  // Route name → YAML asset path
  static const _screens = {
    'onboarding': 'assets/screens/onboarding.yaml',
    'home': 'assets/screens/home.yaml',
    'online': 'assets/screens/online.yaml',
    'heroes': 'assets/screens/heroes.yaml',
    'settings': 'assets/screens/settings.yaml',
    'hero_detail': 'assets/screens/hero_detail.yaml',
    'hero_edit': 'assets/screens/hero_edit.yaml',
  };

  // Widget name → YAML asset path (registered in the widget registry)
  static const _widgetTemplates = {
    'StatChip': 'assets/widgets/stat_chip.yaml',
    'PowerBar': 'assets/widgets/power_bar.yaml',
    'BottomNav': 'assets/widgets/bottom_nav.yaml',
    'ConsentToggle': 'assets/widgets/consent_toggle.yaml',
    'SectionHeader': 'assets/widgets/section_header.yaml',
    'InfoCard': 'assets/widgets/info_card.yaml',
    'ApiField': 'assets/widgets/api_field.yaml',
    'DetailAppBar': 'assets/widgets/detail_app_bar.yaml',
    'OverlayActionButton': 'assets/widgets/overlay_action_button.yaml',
    'YesNoDialog': 'assets/widgets/yes_no_dialog.yaml',
    'ReconcileDialog': 'assets/widgets/reconcile_dialog.yaml',
    'PromptDialog': 'assets/widgets/prompt_dialog.yaml',
    'ConflictDialog': 'assets/widgets/conflict_dialog.yaml',
    'BadgeRow': 'assets/widgets/badge_row.yaml',
    'HeroCardBody': 'assets/widgets/hero_card_body.yaml',
    'DismissibleCard': 'assets/widgets/dismissible_card.yaml',
    'HeroPlaceholder': 'assets/widgets/hero_placeholder.yaml',
  };

  @override
  void initState() {
    super.initState();
    if (widget.authService.isSignedIn) {
      _authenticated = true;
      _initServices();
    } else {
      _initLogin();
    }
  }

  Future<void> _initLogin() async {
    // Construct static bindings fully with all platform boundaries needed
    // for auth.shql (POST to Firebase, SAVE_STATE/LOAD_STATE for tokens).
    WidgetRegistry.initStaticBindings(
      post: http_client.httpPost,
      saveState: _handleSaveState,
      loadState: _handleLoadState,
      nullaryFunctions: {
        // Single Dart boundary: after successful auth, init DB/GoRouter/etc.
        '__ON_AUTHENTICATED': () {
          _onAuthenticated();
          return null;
        },
      },
    );

    final shql = WidgetRegistry.staticShql;

    // Load stdlib + auth.shql (contains all login state, logic, and
    // Firebase Auth functions — _LOGIN_SUBMIT, _LOGIN_TOGGLE_MODE, etc.)
    final stdlibCode = await rootBundle.loadString('packages/shql/assets/stdlib.shql');
    await shql.loadProgram(stdlibCode);
    final authCode = await rootBundle.loadString('assets/shql/auth.shql');
    await shql.loadProgram(authCode);

    // Load login template on the static registry
    final yaml = await rootBundle.loadString('assets/widgets/login_screen.yaml');
    WidgetRegistry.loadStaticTemplate('LoginScreen', yaml);

    if (mounted) setState(() => _loginReady = true);
  }

  Future<void> _initServices() async {
    // Initialize static bindings for dialogs (CLOSE_DIALOG, variable access).
    WidgetRegistry.initStaticBindings();

    // Wire hero_common's injectable callbacks to Flutter dialogs
    Callbacks.configure(
      promptFor: _showPromptDialog,
      promptForYesNo: _showYesNoDialog,
      promptForYes: _showYesNoDialog,
      println: (msg) => debugPrint(msg),
    );

    // Restore per-user preferences: first from local archive ({uid}_{key}),
    // then fill gaps from Firestore cloud. Runs before SHQL™ boots.
    final authUid = widget.prefs.getString('_auth_uid');
    final authToken = widget.prefs.getString('_auth_id_token');

    // 1. Restore from local archive (saved on sign-out)
    debugPrint('[Restore] authUid=$authUid');
    if (authUid != null && authUid.isNotEmpty) {
      for (final key in _syncedKeys) {
        if (widget.prefs.get(key) != null) {
          debugPrint('[Restore] $key already set: ${widget.prefs.get(key)}');
          continue;
        }
        final archiveKey = '${authUid}_$key';
        final archived = widget.prefs.get(archiveKey);
        debugPrint('[Restore] $archiveKey = $archived (${archived.runtimeType})');
        if (archived != null) {
          if (archived is bool) {
            await widget.prefs.setBool(key, archived);
          } else if (archived is int) {
            await widget.prefs.setInt(key, archived);
          } else if (archived is double) {
            await widget.prefs.setDouble(key, archived);
          } else if (archived is String) {
            await widget.prefs.setString(key, archived);
          } else if (archived is List<String>) {
            await widget.prefs.setStringList(key, archived);
          }
        }
      }
    }

    // 2. Fill remaining gaps from Firestore cloud (for cross-device sync)
    if (authUid != null && authToken != null) {
      try {
        final firestoreUrl =
          'https://firestore.googleapis.com/v1/projects/server-driven-ui-flutter'
          '/databases/(default)/documents/preferences/$authUid';
        var token = authToken;
        var cloudData = await http_client.httpFetchAuth(firestoreUrl, token);
        // If token expired, try refreshing via the secure token API
        if (cloudData == null) {
          final refreshToken = widget.prefs.getString('_auth_refresh_token');
          debugPrint('[CloudPrefs] Token failed, refreshToken=${refreshToken != null && refreshToken.isNotEmpty ? "present (${refreshToken.length} chars)" : "MISSING"}');
          if (refreshToken != null && refreshToken.isNotEmpty) {
            final refreshResult = await http_client.httpPost(
              'https://securetoken.googleapis.com/v1/token?key=AIzaSyAi3vFRB12aGVJjTiqIBOpRazJr43kvSkA',
              {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
            );
            debugPrint('[CloudPrefs] Refresh response status: ${refreshResult['status']}');
            if (refreshResult['status'] == 200) {
              final body = refreshResult['body'] as Map<String, dynamic>?;
              if (body != null) {
                final newToken = body['id_token'] as String?;
                final newRefresh = body['refresh_token'] as String?;
                debugPrint('[CloudPrefs] Got new token: ${newToken != null ? "yes (${newToken.length} chars)" : "NO"}');
                if (newToken != null) {
                  await widget.prefs.setString('_auth_id_token', newToken);
                  token = newToken;
                }
                if (newRefresh != null) {
                  await widget.prefs.setString('_auth_refresh_token', newRefresh);
                }
                cloudData = await http_client.httpFetchAuth(firestoreUrl, token);
                debugPrint('[CloudPrefs] Retry result: ${cloudData != null ? "success" : "still failed"}');
              }
            }
          }
        }
        final fields = (cloudData is Map) ? cloudData['fields'] as Map<String, dynamic>? : null;
        if (fields != null) {
          for (final entry in fields.entries) {
            if (widget.prefs.get(entry.key) != null) continue;
            final fv = entry.value as Map<String, dynamic>;
            if (fv.containsKey('booleanValue')) {
              await widget.prefs.setBool(entry.key, fv['booleanValue'] as bool);
            } else if (fv.containsKey('stringValue')) {
              await widget.prefs.setString(entry.key, fv['stringValue'] as String);
            }
          }
        }
      } catch (e) {
        debugPrint('Cloud prefs seed failed: $e');
      }
    }

    final constantsSet = Runtime.prepareConstantsSet();
    HeroShqlAdapter.registerHeroSchema(constantsSet);

    _shqlBindings = ShqlBindings(
      constantsSet: constantsSet,
      onMutated: () => setState(() {}),
      fetch: http_client.httpFetch,
      post: http_client.httpPost,
      patch: http_client.httpPatch,
      fetchAuth: http_client.httpFetchAuth,
      patchAuth: http_client.httpPatchAuth,
      saveState: _handleSaveState,
      loadState: _handleLoadState,
      navigate: (routeName) async {
        final path = routeName.startsWith('/') ? routeName : '/$routeName';
        _router.go(path);
      },
      nullaryFunctions: {
        '_HERO_DATA_CLEAR': () => _coordinator.heroDataClear(),
        '_SIGN_OUT': () async => await _handleSignOut(),
        '_COMPILE_FILTERS': () => _coordinator.compileFilters(),
        '_INIT_RECONCILE': () => _coordinator.initReconcile(),
        '_FINISH_RECONCILE': () => _coordinator.finishReconcile(),
      },
      unaryFunctions: {
        '_BUILD_EDIT_FIELDS': (heroId) {
          if (heroId is String) return _coordinator.buildEditFields(heroId);
          return null;
        },
        '_COMPILE_QUERY': (query) async {
          if (query is String && query.isNotEmpty) {
            return await _coordinator.compileQuery(query);
          }
          return null;
        },
        '_FETCH_HEROES': (query) async {
          if (query is String && query.isNotEmpty) {
            return await _searchService.fetchHeroes(query);
          }
          return null;
        },
        '_GET_SAVED_ID': (hero) => _searchService.getSavedId(hero),
        '_SAVE_HERO': (hero) => _searchService.saveHero(hero),
        '_MAP_HERO': (hero) => _searchService.mapHero(hero),
        '_HERO_DATA_TOGGLE_LOCK': (heroId) {
          if (heroId is String) return _coordinator.heroDataToggleLock(heroId);
          return null;
        },
        '_RECONCILE_FETCH': (heroId) async {
          if (heroId is String) return await _coordinator.reconcileFetch(heroId);
          return null;
        },
        '_RECONCILE_PERSIST': (hero) => _coordinator.reconcilePersist(hero),
        '_RECONCILE_DELETE': (heroId) {
          if (heroId is String) _coordinator.reconcileDelete(heroId);
          return null;
        },
        '_HERO_DATA_DELETE': (heroId) {
          if (heroId is String) return _coordinator.heroDataDelete(heroId);
          return null;
        },
        '_RECONCILE_PROMPT': (text) async =>
            await _coordinator.reconcilePrompt(text?.toString() ?? ''),
        '_SHOW_SNACKBAR': (message) {
          if (message is String) _coordinator.showSnackBar(message);
          return null;
        },
      },
      binaryFunctions: {
        'MATCH': (heroObj, queryText) =>
            _coordinator.matchHeroObject(heroObj, queryText as String),
        '_PROMPT': (prompt, defaultValue) async =>
            await _showPromptDialog(
              prompt?.toString() ?? '',
              defaultValue?.toString() ?? '',
            ),
        '_HERO_DATA_AMEND': (heroId, amendment) async {
          if (heroId is String && heroId.isNotEmpty) {
            return await _coordinator.heroDataAmend(heroId, amendment);
          }
          return null;
        },
        '_ON_PREF_CHANGED': (key, value) {
          if (key is! String) return null;
          switch (key) {
            case 'is_dark_mode':
              if (value is bool && mounted) {
                context.read<ThemeCubit>().set(
                    value ? ThemeMode.dark : ThemeMode.light);
              }
            case 'analytics_enabled':
              if (value is bool) FirebaseService.setAnalyticsEnabled(value);
            case 'crashlytics_enabled':
              if (value is bool) FirebaseService.setCrashlyticsEnabled(value);
            case 'location_enabled':
              _applyLocation(value == true);
          }
          return null;
        },
      },
      ternaryFunctions: {
        '_REVIEW_HERO': (heroObj, current, total) async {
          final c = (current is int) ? current : int.tryParse(current.toString()) ?? 1;
          final t = (total is int) ? total : int.tryParse(total.toString()) ?? 1;
          return await _searchService.reviewHero(heroObj, c, t);
        },
        '_EVAL_PREDICATE': (hero, pred, predicateText) async {
          final text = (predicateText is String) ? predicateText : '';
          if (text.isEmpty) return true;
          if (pred != null) {
            try {
              _predCallTree ??= _shqlBindings.parse('__pred(__hero)');
              final result = await _shqlBindings.evalParsed(
                _predCallTree!,
                boundValues: {'__pred': pred, '__hero': hero},
              );
              if (result is bool) return result;
              return result != null && result != 0;
            } catch (e) {
              // Predicate threw on this hero (e.g. null field) — fall through to text match
            }
          }
          return _coordinator.matchHeroObject(hero, text);
        },
      },
    );

    _heroDataManager = HeroDataManager(
      await HeroRepository.create('herodex_3000.db', SqfliteDriver()),
      runtime: _shqlBindings.runtime,
      constantsSet: _shqlBindings.constantsSet,
    );

    final filterCompiler = FilterCompiler(_shqlBindings);

    _coordinator = HeroCoordinator(
      shqlBindings: _shqlBindings,
      heroDataManager: _heroDataManager,
      filterCompiler: filterCompiler,
      showReconcileDialog: _showReconcileDialog,
      showSnackBar: _showSnackBar,
      onStateChanged: () { if (mounted) setState(() {}); },
    );

    _searchService = HeroSearchService(
      shqlBindings: _shqlBindings,
      heroDataManager: _heroDataManager,
      coordinator: _coordinator,
      navigatorKey: _navigatorKey,
    );

    // Load SHQL™ libraries (order matters — each file may depend on the previous)
    final stdlibCode = await rootBundle.loadString(
      'packages/shql/assets/stdlib.shql',
    );
    await _shqlBindings.loadProgram(stdlibCode);
    await _shqlBindings.eval(HeroSchema.generateSchemaScript());

    const shqlFiles = [
      'auth',         // Firebase auth
      'navigation',   // Route stack & navigation
      'firestore',    // Firestore preferences sync (needs auth)
      'preferences',  // Theme, onboarding, API config (needs firestore)
      'statistics',   // Running totals & derived stats
      'filters',      // Filter system & predicates (needs statistics)
      'heroes',       // Hero collection CRUD (needs stats, filters, nav, auth)
      'hero_detail',  // Detail view generation (needs heroes, schema)
      'hero_cards',   // Card generation (needs heroes, filters, stats)
      'search',       // Hero search & history (needs hero_cards)
      'hero_edit',    // Hero edit form (needs heroes, nav, schema)
      'world',        // Weather, battle map, location, war status
    ];
    for (final name in shqlFiles) {
      final code = await rootBundle.loadString('assets/shql/$name.shql');
      await _shqlBindings.loadProgram(code);
    }

    final heroDexRegistry = createHeroDexWidgetRegistry();
    _yamlEngine = YamlUiEngine(_shqlBindings, heroDexRegistry);

    // Register custom Dart factories on the static registry so that
    // imperative Dart screens (HeroCard, etc.) can use buildStatic too.
    registerStaticFactories(heroDexRegistry);

    // Load YAML-defined widget templates into both the engine registry
    // (for SHQL™-driven screens) and the static registry (for imperative
    // Dart screens like login, splash, and dialogs).
    for (final entry in _widgetTemplates.entries) {
      final yaml = await rootBundle.loadString(entry.value);
      _yamlEngine.loadWidgetTemplate(entry.key, yaml);
      WidgetRegistry.loadStaticTemplate(entry.key, yaml);
    }

    // Filter and query changes are handled directly in SHQL™:
    // - __PERSIST_FILTERS() calls FULL_REBUILD_AND_DISPLAY() after mutating filters
    // - APPLY_QUERY sets current_query, then ON_QUERY_CHANGED_AND_REBUILD() is called
    //   by the SHQL caller (filter_editor calls APPLY_QUERY then the Dart listener used
    //   to trigger ON_QUERY_CHANGED). Now SHQL handles this directly.
    // No Dart listeners needed — SHQL drives the orchestration.

    // Initialize hero data (stats are updated per-hero inside initialize),
    // then build filter results. Stats are already correct by the time
    // filters are compiled, so predicates like "Giants" see current avg/stdev.
    if (mounted) setState(() => _loadingStatus = 'Loading heroes...');
    await _coordinator.initializeHeroes();
    if (mounted) setState(() => _loadingStatus = 'Building filters...');
    try {
      await _coordinator.rebuildAllFilters();
    } catch (e) {
      debugPrint('rebuildAllFilters failed at startup: $e');
    }
    if (mounted) setState(() => _loadingStatus = '');
    await _coordinator.populateHeroCardCache();

    // Read all initial preferences in one SHQL™ call (Rule 2: batch reads)
    final initState = _shqlBindings.objectToMap(
        await _shqlBindings.eval('Prefs.GET_INIT_STATE()'));
    final initialRoute = initState['onboarding_completed'] == true ? 'home' : 'onboarding';

    _router = GoRouter(
      navigatorKey: _navigatorKey,
      initialLocation: '/$initialRoute',
      routes: [
        for (final entry in _screens.entries)
          GoRoute(
            path: '/${entry.key}',
            builder: (context, state) => YamlScreen(
              yamlAsset: entry.value,
              engine: _yamlEngine,
            ),
          ),
      ],
    );

    // Apply initial preferences from restored state.
    // Ongoing changes are pushed by SHQL™ via _ON_PREF_CHANGED(key, value)
    // called from Prefs.__SAVE — no listeners needed.
    final initialDarkMode = initState['is_dark_mode'];
    if (initialDarkMode is bool && mounted) {
      context.read<ThemeCubit>().set(initialDarkMode ? ThemeMode.dark : ThemeMode.light);
    }
    final analyticsEnabled = initState['analytics_enabled'];
    if (analyticsEnabled is bool) await FirebaseService.setAnalyticsEnabled(analyticsEnabled);
    final crashlyticsEnabled = initState['crashlytics_enabled'];
    if (crashlyticsEnabled is bool) await FirebaseService.setCrashlyticsEnabled(crashlyticsEnabled);
    if (initState['location_enabled'] == true) {
      _applyLocation(true);
    }

    _connectivityService = ConnectivityService();
    _connectivityService!.connectivityStream.listen((isConnected) {
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(isConnected ? 'Back online' : 'No internet connection'),
            ],
          ),
          backgroundColor: isConnected ? Colors.green : Colors.red,
          duration: Duration(seconds: isConnected ? 2 : 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });

    setState(() {
      _initialized = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Dialog helpers — delegate to top-level functions in widgets/dialogs.dart
  // ---------------------------------------------------------------------------

  Future<String> _showPromptDialog(String prompt, [String defaultValue = '']) =>
      dialogs.showPromptDialog(_navigatorKey, _scaffoldMessengerKey, prompt, defaultValue);

  Future<bool> _showYesNoDialog(String prompt) =>
      dialogs.showYesNoDialog(_navigatorKey, prompt);

  Future<ReviewAction> _showReconcileDialog(String prompt) =>
      dialogs.showReconcileDialog(_navigatorKey, prompt);

  // ---------------------------------------------------------------------------
  // SHQL™ helpers
  // ---------------------------------------------------------------------------

  Future<void> _applyLocation(bool enabled) async {
    final desc = enabled ? await LocationService.getLocationDescription() : '';
    final coords = enabled ? await LocationService.getCoordinates() : null;
    await _shqlBindings.eval('World.SET_LOCATION(__desc, __lat, __lon)',
        boundValues: {'__desc': desc, '__lat': coords?.$1, '__lon': coords?.$2});
    if (enabled && mounted) setState(() {});
  }

  void _showSnackBar(String message) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ---------------------------------------------------------------------------
  // State persistence (bridge between SHQL™ + SharedPreferences + Firestore)
  // ---------------------------------------------------------------------------

  Future<void> _handleSaveState(String key, dynamic value) async {
    if (value == null) {
      await widget.prefs.remove(key);
    } else if (value is bool) {
      await widget.prefs.setBool(key, value);
    } else if (value is int) {
      await widget.prefs.setInt(key, value);
    } else if (value is double) {
      await widget.prefs.setDouble(key, value);
    } else if (value is String) {
      await widget.prefs.setString(key, value);
    } else if (value is List && value.isNotEmpty && _shqlBindings.isShqlObject(value.first)) {
      final jsonList = value.map((e) => _shqlBindings.objectToMap(e)).toList();
      await widget.prefs.setString(key, jsonEncode(jsonList));
    } else if (value is List) {
      await widget.prefs.setStringList(
        key,
        value.map((e) => e.toString()).toList(),
      );
    } else {
      await widget.prefs.setString(key, value.toString());
    }
    // Firestore sync is now handled by SAVE_PREF() in SHQL™
  }

  Future<dynamic> _handleLoadState(String key, dynamic defaultValue) async {
    final value = widget.prefs.get(key);
    if (value == null || value == 'null') return defaultValue;
    if (defaultValue is List && defaultValue.isNotEmpty && _shqlBindings.isShqlObject(defaultValue.first)) {
      if (value is String) {
        try {
          final decoded = jsonDecode(value) as List;
          return decoded
              .map((item) => _shqlBindings.mapToObject(Map<String, dynamic>.from(item as Map)))
              .toList();
        } catch (_) {
          return defaultValue;
        }
      }
      return defaultValue;
    }
    if (defaultValue is bool && value is String) {
      return value.toLowerCase() == 'true';
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  void _onAuthenticated() {
    setState(() => _authenticated = true);
    _initServices();
  }

  static const _syncedKeys = [
    'is_dark_mode', 'api_key', 'api_host', 'onboarding_completed',
    'analytics_enabled', 'crashlytics_enabled', 'location_enabled', 'filters',
  ];

  Future<void> _handleSignOut() async {
    // FIREBASE_SIGN_OUT() already cleared _auth_uid from SharedPreferences
    // (via SAVE_STATE(…, null)), so read the UID from the SHQL™ runtime
    // where it still holds the old value.
    final uid = (await _shqlBindings.eval('Cloud.auth_uid'))?.toString();
    debugPrint('[SignOut] uid from runtime: $uid');

    // Archive per-user preferences under {uid}_ prefix so they can be
    // restored when this user signs back in, then clear bare keys.
    for (final key in _syncedKeys) {
      final value = widget.prefs.get(key);
      debugPrint('[SignOut] $key = $value (${value.runtimeType})');
      if (uid != null && uid.isNotEmpty && value != null) {
        final archiveKey = '${uid}_$key';
        debugPrint('[SignOut] archiving $key → $archiveKey');
        if (value is bool) {
          await widget.prefs.setBool(archiveKey, value);
        } else if (value is int) {
          await widget.prefs.setInt(archiveKey, value);
        } else if (value is double) {
          await widget.prefs.setDouble(archiveKey, value);
        } else if (value is String) {
          await widget.prefs.setString(archiveKey, value);
        } else if (value is List<String>) {
          await widget.prefs.setStringList(archiveKey, value);
        }
      }
      await widget.prefs.remove(key);
    }
    setState(() {
      _authenticated = false;
      _initialized = false;
    });
    _initLogin();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_authenticated) {
      return BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'HeroDex 3000',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: _loginReady
                ? WidgetRegistry.buildStatic(context, {'type': 'LoginScreen', 'props': {}}, 'login')
                : const SizedBox.shrink(),
          );
        },
      );
    }

    if (!_initialized) {
      final progressChildren = <dynamic>[
        {'type': 'CircularProgressIndicator', 'props': {'valueColor': '0xFFFFFFFF'}},
        if (_loadingStatus.isNotEmpty) ...[
          {'type': 'SizedBox', 'props': {'height': 16}},
          {'type': 'Text', 'props': {
            'data': _loadingStatus,
            'style': {'fontSize': 14, 'color': '0xB3FFFFFF', 'fontFamily': 'Orbitron'},
          }},
        ],
      ];

      return BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: WidgetRegistry.buildStatic(context, {'type': 'Scaffold', 'props': {
              'backgroundColor': '0xFF1A237E',
              'body': {'type': 'Center', 'child': {
                'type': 'Column', 'props': {
                  'mainAxisAlignment': 'center',
                  'children': [
                    {'type': 'Icon', 'props': {'icon': 'shield', 'size': 100, 'color': '0xFFFFFFFF'}},
                    {'type': 'SizedBox', 'props': {'height': 24}},
                    {'type': 'Text', 'props': {
                      'data': 'HeroDex 3000',
                      'style': {'fontSize': 32, 'fontWeight': 'bold', 'color': '0xFFFFFFFF', 'fontFamily': 'Orbitron'},
                    }},
                    {'type': 'SizedBox', 'props': {'height': 48}},
                    ...progressChildren,
                  ],
                },
              }},
            }}, 'splash'),
          );
        },
      );
    }

    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, themeMode) {
        return MaterialApp.router(
          title: 'HeroDex 3000',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          routerConfig: _router,
        );
      },
    );
  }

  @override
  void dispose() {
    _connectivityService?.dispose();
    _heroDataManager.dispose();
    super.dispose();
  }
}
