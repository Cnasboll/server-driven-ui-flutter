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
import 'persistence/shql_hero_data_manager.dart';
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
  late ShqlHeroDataManager _heroDataManager;
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
  int _loadingProgress = 0;
  int _loadingTotal = 0;
  String _loadingHeroName = '';

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
        final cloudData = await http_client.httpFetchAuth(
          'https://firestore.googleapis.com/v1/projects/server-driven-ui-flutter'
          '/databases/(default)/documents/preferences/$authUid',
          authToken,
        );
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
        '_CLEAR_ALL_DATA': () async => await _coordinator.clearData(),
        '_RECONCILE_HEROES': () async => await _coordinator.reconcile(),
        '_SIGN_OUT': () async => await _handleSignOut(),
        '_PREPARE_EDIT': () => _coordinator.prepareEdit(),
      },
      unaryFunctions: {
        '_FETCH_HEROES': (query) async {
          if (query is String && query.isNotEmpty) {
            await _searchService.search(query);
          }
        },
        '_PERSIST_HERO': (externalId) async {
          if (externalId is String && externalId.isNotEmpty) {
            await _searchService.saveHero(externalId);
          }
        },
        'DELETE_HERO': (heroId) async {
          if (heroId is String && heroId.isNotEmpty) {
            await _coordinator.deleteHero(heroId);
            _searchService.publishSearchResults();
          }
        },
        '_APPLY_AMENDMENT': (heroId) async {
          if (heroId is String && heroId.isNotEmpty) {
            await _coordinator.amendHero(heroId);
          }
        },
        '_TOGGLE_LOCK_HERO': (heroId) async {
          if (heroId is String && heroId.isNotEmpty) {
            await _coordinator.toggleLock(heroId);
          }
        },
      },
      binaryFunctions: {
        'MATCH': (heroObj, queryText) =>
            _coordinator.matchHeroObject(heroObj, queryText as String),
      },
      ternaryFunctions: {
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

    _heroDataManager = ShqlHeroDataManager(
      HeroDataManager(
        await HeroRepository.create('herodex_3000.db', SqfliteDriver()),
        runtime: _shqlBindings.runtime,
        constantsSet: _shqlBindings.constantsSet,
      ),
      _shqlBindings,
    );

    final filterCompiler = FilterCompiler(_shqlBindings);

    _coordinator = HeroCoordinator(
      shqlBindings: _shqlBindings,
      heroDataManager: _heroDataManager,
      filterCompiler: filterCompiler,
      showPromptDialog: _showPromptDialog,
      showReconcileDialog: _showReconcileDialog,
      showSnackBar: _showSnackBar,
      onStateChanged: () { if (mounted) setState(() {}); },
    );

    _searchService = HeroSearchService(
      shqlBindings: _shqlBindings,
      heroDataManager: _heroDataManager,
      coordinator: _coordinator,
      navigatorKey: _navigatorKey,
      onStateChanged: () { if (mounted) setState(() {}); },
    );

    // Load SHQL™ libraries
    final stdlibCode = await rootBundle.loadString(
      'packages/shql/assets/stdlib.shql',
    );
    final authCode = await rootBundle.loadString('assets/shql/auth.shql');
    final herodexCode = await rootBundle.loadString('assets/shql/herodex.shql');

    await _shqlBindings.loadProgram(stdlibCode);
    await _shqlBindings.eval(HeroSchema.generateSchemaScript());
    await _shqlBindings.loadProgram(authCode);
    await _shqlBindings.loadProgram(herodexCode);

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

    // Filter orchestration listeners
    _shqlBindings.addListener('_filters', () {
      _coordinator.onFiltersChanged();
    });
    // Note: _active_filter_index changes are handled by APPLY_FILTER() in SHQL™,
    // which calls UPDATE_DISPLAYED_HEROES() → SET('_displayed_heroes'). The
    // listener below then rebuilds _hero_cards from the Dart cache.
    _shqlBindings.addListener('_displayed_heroes', () {
      _coordinator.onDisplayedHeroesChanged();
    });
    _shqlBindings.addListener('_current_query', () {
      _coordinator.onQueryChanged();
    });

    // Initialize hero data (stats are updated per-hero inside initialize),
    // then build filter results. Stats are already correct by the time
    // filters are compiled, so predicates like "Giants" see current avg/stdev.
    if (mounted) setState(() => _loadingStatus = 'Loading heroes...');
    await _heroDataManager.initialize();
    if (mounted) setState(() => _loadingStatus = 'Building filters...');
    try {
      await _coordinator.rebuildAllFilters();
    } catch (e) {
      debugPrint('rebuildAllFilters failed at startup: $e');
    }
    if (mounted) setState(() => _loadingStatus = '');
    await _coordinator.populateHeroCardCache(
      onProgress: (current, total, heroName) {
        if (mounted) {
          setState(() {
            _loadingProgress = current;
            _loadingTotal = total;
            _loadingHeroName = heroName;
          });
        }
      },
    );

    // Determine initial route
    final onboardingCompleted = _shqlBindings.getVariable('_onboarding_completed');
    final initialRoute = onboardingCompleted == true ? 'home' : 'onboarding';

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

    // Sync SHQL™ dark mode changes → ThemeCubit
    _shqlBindings.addListener('_is_dark_mode', () {
      final value = _shqlBindings.getVariable('_is_dark_mode');
      if (value is bool && mounted) {
        final cubit = context.read<ThemeCubit>();
        cubit.set(value ? ThemeMode.dark : ThemeMode.light);
      }
    });

    // Apply initial dark mode from restored preferences
    final initialDarkMode = _shqlBindings.getVariable('_is_dark_mode');
    if (initialDarkMode is bool && mounted) {
      context.read<ThemeCubit>().set(initialDarkMode ? ThemeMode.dark : ThemeMode.light);
    }

    // Apply initial Firebase consent and listen for changes
    final analyticsEnabled = _shqlBindings.getVariable('_analytics_enabled');
    if (analyticsEnabled is bool) await FirebaseService.setAnalyticsEnabled(analyticsEnabled);
    final crashlyticsEnabled = _shqlBindings.getVariable('_crashlytics_enabled');
    if (crashlyticsEnabled is bool) await FirebaseService.setCrashlyticsEnabled(crashlyticsEnabled);

    _shqlBindings.addListener('_analytics_enabled', () {
      final v = _shqlBindings.getVariable('_analytics_enabled');
      if (v is bool) FirebaseService.setAnalyticsEnabled(v);
    });
    _shqlBindings.addListener('_crashlytics_enabled', () {
      final v = _shqlBindings.getVariable('_crashlytics_enabled');
      if (v is bool) FirebaseService.setCrashlyticsEnabled(v);
    });

    _shqlBindings.addListener('_location_enabled', () async {
      final enabled = _shqlBindings.getVariable('_location_enabled');
      await _applyLocation(enabled == true);
    });

    // Apply initial location from restored preferences
    final initialLocationEnabled = _shqlBindings.getVariable('_location_enabled');
    if (initialLocationEnabled == true) {
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

  void _setAndNotify(String name, dynamic value) {
    _shqlBindings.setVariable(name, value);
    _shqlBindings.notifyListeners(name);
  }

  Future<void> _applyLocation(bool enabled) async {
    if (enabled) {
      final desc = await LocationService.getLocationDescription();
      _setAndNotify('_location_description', desc);
      final coords = await LocationService.getCoordinates();
      if (coords != null) {
        _setAndNotify('_user_latitude', coords.$1);
        _setAndNotify('_user_longitude', coords.$2);
      }
      if (mounted) setState(() {});
    } else {
      _setAndNotify('_location_description', '');
    }
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
    final uid = _shqlBindings.getVariable('_auth_uid') as String?;
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
      final hasProgress = _loadingTotal > 0;
      final progressChildren = <dynamic>[
        if (hasProgress) ...[
          {'type': 'Padding', 'props': {
            'padding': {'left': 48, 'right': 48},
            'child': {'type': 'LinearProgressIndicator', 'props': {
              'value': _loadingProgress / _loadingTotal,
              'backgroundColor': '0x3DFFFFFF',
              'valueColor': '0xFFFFFFFF',
              'minHeight': 6,
              'borderRadius': 3,
            }},
          }},
          {'type': 'SizedBox', 'props': {'height': 16}},
          {'type': 'Text', 'props': {
            'data': _loadingHeroName.isNotEmpty
                ? '$_loadingHeroName ($_loadingProgress/$_loadingTotal)'
                : '$_loadingProgress / $_loadingTotal',
            'style': {'fontSize': 14, 'color': '0xB3FFFFFF', 'fontFamily': 'Orbitron'},
          }},
        ] else ...[
          {'type': 'CircularProgressIndicator', 'props': {'valueColor': '0xFFFFFFFF'}},
          if (_loadingStatus.isNotEmpty) ...[
            {'type': 'SizedBox', 'props': {'height': 16}},
            {'type': 'Text', 'props': {
              'data': _loadingStatus,
              'style': {'fontSize': 14, 'color': '0xB3FFFFFF', 'fontFamily': 'Orbitron'},
            }},
          ],
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
