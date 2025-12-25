import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:server_driven_ui/screen_cubit/screen_cubit.dart';
import 'package:server_driven_ui/yaml_ui/shql_bindings.dart';
import 'package:server_driven_ui/yaml_ui/widget_registry.dart';
import 'package:server_driven_ui/yaml_ui/yaml_ui_engine.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final routerSource = await rootBundle.loadString('assets/router.yaml');
  final routes = loadYaml(routerSource)['routes'] as YamlMap;

  final stdlibSource = await rootBundle.loadString('packages/shql/assets/stdlib.shql');
  final uiSource = await rootBundle.loadString('assets/shql/ui.shql');
  runApp(
    MyApp(
      routes: routes.cast<String, String>(),
      stdlibSource: stdlibSource,
      uiSource: uiSource,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.routes,
    required this.stdlibSource,
    required this.uiSource,
  });

  final Map<String, String> routes;
  final String stdlibSource;
  final String uiSource;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: BlocProvider(
        create: (context) => ScreenCubit(),
        child: YamlDrivenScreen(
          routes: routes,
          initialRoute: 'main',
          stdlibSource: stdlibSource,
          uiSource: uiSource,
        ),
      ),
    );
  }
}

class YamlDrivenScreen extends StatefulWidget {
  const YamlDrivenScreen({
    super.key,
    required this.routes,
    required this.initialRoute,
    required this.stdlibSource,
    required this.uiSource,
  });

  final Map<String, String> routes;
  final String initialRoute;
  final String stdlibSource;
  final String uiSource;

  @override
  State<YamlDrivenScreen> createState() => _YamlDrivenScreenState();
}

class _YamlDrivenScreenState extends State<YamlDrivenScreen> {
  YamlUiEngine? _engine;
  dynamic _resolvedUiData;
  bool _isLoading = true;
  Object? _error;
  final List<String> _logs = [];
  late String _currentYamlSource;

  @override
  void initState() {
    super.initState();
    _initAndResolve();
  }

  Future<void> _navigate(String routeName) async {
    if (!widget.routes.containsKey(routeName)) {
      // ignore: avoid_print
      print("Route '$routeName' not found!");
      return;
    }
    final yamlPath = widget.routes[routeName]!;
    final newYamlSource = await rootBundle.loadString(yamlPath);

    setState(() {
      _currentYamlSource = newYamlSource;
      _isLoading = true; // Show loading indicator while resolving new UI
    });

    // Update Cubit state (BLoC pattern)
    if (mounted) {
      context.read<ScreenCubit>().setLoading();
    }

    await _resolveUi();
  }

  Future<dynamic> _fetch(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        // You might want to return an error object or throw
        return null;
      }
    } catch (e) {
      // Handle exceptions like invalid URL, no network, etc.
      return null;
    }
  }

  Future<void> _saveState(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else {
      // Serialize complex types (arrays, objects) to JSON
      await prefs.setString(key, jsonEncode(value));
    }
  }

  Future<dynamic> _loadState(String key, dynamic defaultValue) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get(key);

    if (value == null) {
      return defaultValue;
    }

    // If it's a string, try to decode it as JSON (for complex types)
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (e) {
        // If JSON decoding fails, return the string as-is
        return value;
      }
    }

    return value;
  }

  Future<void> _initAndResolve() async {
    try {
      // Load initial YAML source
      final initialYamlPath = widget.routes[widget.initialRoute]!;
      _currentYamlSource = await rootBundle.loadString(initialYamlPath);

      final shql = ShqlBindings(
        onMutated: () {
          if (!mounted) return;
          _resolveUi();
        },
        printLine: (value) {
          if (!mounted) return;
          setState(() {
            _logs.add(value.toString());
          });
        },
        debugLog: (message) {
          if (!mounted) return;
          setState(() {
            _logs.add(
              '[${DateTime.now().toString().substring(11, 19)}] $message',
            );
          });
        },
        readline: () async => null,
        prompt: (_) async => null,
        navigate: _navigate,
        fetch: _fetch,
        saveState: _saveState,
        loadState: _loadState,
      );

      // Sequentially load the programs.
      await shql.loadProgram(widget.stdlibSource);
      await shql.loadProgram(widget.uiSource);

      final engine = YamlUiEngine(shql, WidgetRegistry.basic());
      setState(() {
        _engine = engine;
      });

      // Perform the initial UI resolution.
      await _resolveUi();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
        // Update Cubit state (BLoC pattern)
        context.read<ScreenCubit>().setError(e.toString());
      }
    }
  }

  Future<void> _resolveUi() async {
    if (_engine == null) return;
    try {
      final data = await _engine!.resolve(_currentYamlSource);
      if (mounted) {
        setState(() {
          _resolvedUiData = data;
          _isLoading = false;
          _error = null;
        });
        // Update Cubit state (BLoC pattern)
        context.read<ScreenCubit>().setLoaded();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
        // Update Cubit state (BLoC pattern)
        context.read<ScreenCubit>().setError(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Material(child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Material(
        child: Center(
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    if (_engine != null && _resolvedUiData != null) {
      return Material(
        child: Column(
          children: [
            Expanded(child: _engine!.build(_resolvedUiData, context)),
            Container(
              height: 200,
              color: Colors.grey[200],
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Text(_logs[index]);
                },
              ),
            ),
          ],
        ),
      );
    }
    // Should not happen, but provides a fallback.
    return const Material(child: Center(child: Text('Engine not initialized')));
  }
}
