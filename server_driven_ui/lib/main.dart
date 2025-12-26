import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:server_driven_ui/yaml_ui/shql_bindings.dart';
import 'package:server_driven_ui/yaml_ui/widget_registry.dart';
import 'package:server_driven_ui/yaml_ui/yaml_ui_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final yamlSource = await rootBundle.loadString('assets/ui.yaml');
  final stdlibSource = await rootBundle.loadString('assets/shql/stdlib.shql');
  final uiSource = await rootBundle.loadString('assets/shql/ui.shql');
  runApp(
    MyApp(
      yamlSource: yamlSource,
      stdlibSource: stdlibSource,
      uiSource: uiSource,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.yamlSource,
    required this.stdlibSource,
    required this.uiSource,
  });

  final String yamlSource;
  final String stdlibSource;
  final String uiSource;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: YamlDrivenScreen(
        yamlSource: yamlSource,
        stdlibSource: stdlibSource,
        uiSource: uiSource,
      ),
    );
  }
}

class YamlDrivenScreen extends StatefulWidget {
  const YamlDrivenScreen({
    super.key,
    required this.yamlSource,
    required this.stdlibSource,
    required this.uiSource,
  });

  final String yamlSource;
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

  @override
  void initState() {
    super.initState();
    _initAndResolve();
  }

  Future<void> _initAndResolve() async {
    try {
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
      );

      // Sequentially load the programs.
      await shql.loadProgram(widget.stdlibSource, name: 'standard library');
      await shql.loadProgram(widget.uiSource, name: 'UI script');

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
      final data = await _engine!.resolve(widget.yamlSource);
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
