import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:server_driven_ui/yaml_ui/shql_bindings.dart';
import 'package:server_driven_ui/yaml_ui/widget_registry.dart';
import 'package:server_driven_ui/yaml_ui/yaml_ui_engine.dart';
import 'package:yaml/yaml.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final routerSource = await rootBundle.loadString('assets/router.yaml');
  final routes = loadYaml(routerSource)['routes'] as YamlMap;

  final stdlibSource = await rootBundle.loadString('assets/shql/stdlib.shql');
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
      home: YamlDrivenScreen(
        routes: routes,
        initialRoute: 'main',
        stdlibSource: stdlibSource,
        uiSource: uiSource,
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
        readline: () async => null,
        prompt: (_) async => null,
        navigate: _navigate,
        fetch: _fetch,
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
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
