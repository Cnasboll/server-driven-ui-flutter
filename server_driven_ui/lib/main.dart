import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'yaml_ui/yaml_ui_engine.dart';
import 'yaml_ui/widget_registry.dart';
import 'yaml_ui/shql_bindings.dart';

// TODO: Replace these imports with your interpreter/runtime types.
// import 'your_shql/runtime.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YAML + SHQL UI',
      theme: ThemeData(useMaterial3: true),
      home: const YamlDrivenScreen(),
    );
  }
}

class YamlDrivenScreen extends StatefulWidget {
  const YamlDrivenScreen({super.key});
  @override
  State<YamlDrivenScreen> createState() => _YamlDrivenScreenState();
}

class _YamlDrivenScreenState extends State<YamlDrivenScreen> {
  String? _yamlText;
  late final WidgetRegistry _registry;

  late final ShqlBindings _shql; // wraps your async runtime
  late final YamlUiEngine _engine;

  // Example: a simple console panel fed by SHQL PRINT
  final List<String> _console = [];

  @override
  void initState() {
    super.initState();

    _registry = WidgetRegistry.basic();

    _shql = ShqlBindings(
      // Replace with your runtime instance:
      onMutated: () => setState(() {}),
      printLine: (line) {
        setState(() => _console.add(line));
      },
      readline: () => Future.value(null),
      // Optional: provide UI helpers for externs
      prompt: (message) => _promptDialog(context, message),
    );

    _engine = YamlUiEngine(
      registry: _registry,
      shql: _shql,
      onErrorWidget: (title, details) =>
          _ErrorPanel(title: title, details: details),
    );

    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final yaml = await rootBundle.loadString('assets/ui.yaml');
    final stdlibCode = await rootBundle.loadString('assets/shql/stdlib.shql');
    await _shql.loadProgram(
      stdlibCode,
      "Loading standard library...",
      "Standard library loaded.",
      "Failed to load standard library.",
    );

    final programCode = await rootBundle.loadString('assets/shql/state.shql');
    await _shql.loadProgram(
      programCode,
      "Loading state script...",
      "State script loaded.",
      "Failed to load state script.",
    );

    final listUtilsCode = await rootBundle.loadString(
      'assets/shql/list_utils.shql',
    );
    await _shql.loadProgram(
      listUtilsCode,
      "Loading list utils...",
      "List utils loaded.",
      "Failed to load list utils.",
    );

    setState(() {
      _yamlText = yaml;
    });
  }

  Future<String?> _promptDialog(BuildContext context, String message) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Input'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(controller: controller, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_yamlText == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ui = _engine.buildFromYamlString(_yamlText!, context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: ui),
            if (_console.isNotEmpty)
              SizedBox(
                height: 160,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _console.length,
                    itemBuilder: (ctx, i) => Text(_console[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String title;
  final String details;
  const _ErrorPanel({required this.title, required this.details});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(details),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Dummy runtime so the scaffold compiles. Replace with your real Runtime.
/// ---------------------------------------------------------------------------
class DummyRuntime {
  Future<void> load(String program) async {}
  Future<dynamic> evalExpr(String expr) async => null;
  Future<dynamic> call(String code) async => null;
}
