import 'package:flutter/widgets.dart';
import 'package:yaml/yaml.dart';

import 'widget_registry.dart';
import 'shql_bindings.dart';

typedef ErrorWidgetBuilder = Widget Function(String title, String details);

class YamlUiEngine {
  final WidgetRegistry registry;
  final ShqlBindings shql;
  final ErrorWidgetBuilder onErrorWidget;

  YamlUiEngine({
    required this.registry,
    required this.shql,
    required this.onErrorWidget,
  });

  Widget buildFromYamlString(String yamlText, BuildContext context) {
    try {
      final doc = loadYaml(yamlText);
      final root = _normalize(doc);
      if (root is! Map<String, dynamic>) {
        return onErrorWidget(
          'YAML root must be a map',
          'Found: ${root.runtimeType}',
        );
      }
      final screen = root['screen'] ?? root['ui'] ?? root;
      return buildNode(screen, context, path: r'$');
    } catch (e, st) {
      return onErrorWidget('YAML parse/build error', '$e\n\n$st');
    }
  }

  Widget buildNode(dynamic node, BuildContext context, {required String path}) {
    try {
      if (node == null) return const SizedBox.shrink();
      final n = _normalize(node);

      if (n is Map<String, dynamic>) {
        final type = n['type']?.toString();
        if (type == null) {
          return onErrorWidget('Missing "type"', 'Path: $path');
        }
        final props = (n['props'] is Map)
            ? Map<String, dynamic>.from(n['props'] as Map)
            : <String, dynamic>{};
        final child = n.containsKey('child') ? n['child'] : null;
        final children = n['children'];

        return registry.build(
          type: type,
          context: context,
          props: props,
          buildChild: (dyn, childPath) =>
              buildNode(dyn, context, path: childPath),
          child: child,
          children: children,
          path: path,
          shql: shql,
        );
      }

      // Allow shorthand text node: "Hello"
      if (n is String) {
        return registry.build(
          type: 'Text',
          context: context,
          props: {'data': n},
          buildChild: (_, __) => const SizedBox.shrink(),
          child: null,
          children: null,
          path: path,
          shql: shql,
        );
      }

      return onErrorWidget(
        'Unsupported node',
        'Path: $path\nFound: ${n.runtimeType}',
      );
    } catch (e, st) {
      return onErrorWidget('Build error', 'Path: $path\n$e\n\n$st');
    }
  }

  dynamic _normalize(dynamic v) {
    if (v is YamlMap) {
      return v.map((k, val) => MapEntry(k.toString(), _normalize(val)));
    }
    if (v is YamlList) {
      return v.map(_normalize).toList();
    }
    return v;
  }
}
