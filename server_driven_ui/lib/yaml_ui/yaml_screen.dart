import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'yaml_ui_engine.dart';

/// A widget that renders a YAML screen definition loaded from an asset file.
class YamlScreen extends StatefulWidget {
  final String yamlAsset;
  final YamlUiEngine engine;

  const YamlScreen({super.key, required this.yamlAsset, required this.engine});

  @override
  State<YamlScreen> createState() => _YamlScreenState();
}

class _YamlScreenState extends State<YamlScreen> {
  dynamic _resolvedData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAndResolve();
  }

  @override
  void didUpdateWidget(covariant YamlScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yamlAsset != widget.yamlAsset) {
      _loadAndResolve();
    }
  }

  Future<void> _loadAndResolve() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final yamlContent = await rootBundle.loadString(widget.yamlAsset);
      final resolved = await widget.engine.resolve(yamlContent);
      if (mounted) {
        setState(() {
          _resolvedData = resolved;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error building UI: $_error'),
            ],
          ),
        ),
      );
    }

    return widget.engine.build(_resolvedData, context);
  }
}
