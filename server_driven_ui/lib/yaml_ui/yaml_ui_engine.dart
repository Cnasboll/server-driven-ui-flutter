import 'dart:async';

import 'package:flutter/material.dart';
import 'package:server_driven_ui/yaml_ui/shql_bindings.dart';
import 'package:server_driven_ui/yaml_ui/widget_registry.dart';
import 'package:yaml/yaml.dart';

class YamlUiEngine {
  final ShqlBindings shql;
  final WidgetRegistry registry;

  YamlUiEngine(this.shql, this.registry);

  /// Asynchronously resolves all `shql:` expressions in the YAML tree.
  Future<dynamic> resolve(String yaml) async {
    final data = loadYaml(yaml);

    // Check for and execute onLoad at the top level (before extracting screen)
    if (data is YamlMap && data.containsKey('onLoad')) {
      final onLoadShql = data['onLoad'] as String?;
      if (onLoadShql != null && isShqlRef(onLoadShql)) {
        final (:code, :targeted) = parseShql(onLoadShql);
        // Fire and forget. The mutation will trigger a rebuild.
        shql.call(code, targeted: targeted);
      }
    }

    final rootNode = (data is YamlMap && data.containsKey('screen'))
        ? data['screen']
        : data;

    // After handling onLoad, resolve the actual widget tree
    final widgetNode = (rootNode is YamlMap && rootNode.containsKey('widget'))
        ? rootNode['widget']
        : rootNode;

    return _resolveNode(widgetNode);
  }

  /// Loads a YAML widget template and registers it in the widget registry
  /// under [name]. The template can use `"prop:xyz"` placeholders that are
  /// substituted with the caller's props at build time.
  void loadWidgetTemplate(String name, String yaml) {
    final data = loadYaml(yaml);
    final template = (data is YamlMap && data.containsKey('widget'))
        ? data['widget']
        : data;
    registry.registerTemplate(name, template);
  }

  /// Synchronously builds the widget tree from a fully resolved data structure.
  Widget build(dynamic resolvedData, BuildContext context) {
    return _buildWidget(resolvedData, context, 'screen');
  }

  Widget _buildWidget(dynamic node, BuildContext context, String path) {
    if (node is Widget) return node;
    if (node is Map && node.containsKey('type')) {
      final type = node['type'] as String;
      final props = (node['props'] as Map?) ?? {};
      final child = node['child'] ?? props['child'];
      final children = node['children'] ?? props['children'];

      return registry.build(
        type: type,
        context: context,
        props: Map<String, dynamic>.from(props),
        buildChild: (node, childPath) => _buildWidget(node, context, childPath),
        child: child,
        children: children,
        path: path,
        shql: shql,
        engine: this,
      );
    }

    if (node is List) {
      return const SizedBox.shrink();
    }

    return Text(node?.toString() ?? 'null');
  }

  Future<dynamic> _resolveNode(dynamic node) async {
    if (node is String) {
      if (isShqlRef(node)) {
        final expression = parseShql(node).code;
        final result = await shql.eval(expression);
        return _resolveNode(result);
      }
      return node;
    }

    if (node is YamlMap) {
      final newMap = <String, dynamic>{};
      for (final key in node.keys) {
        final value = node[key];

        if (node['type'] == 'Observer' && key == 'props' && value is YamlMap) {
          final newProps = <String, dynamic>{};
          for (final propKey in value.keys) {
            if (propKey == 'builder') {
              newProps[propKey] = value[propKey];
            } else {
              newProps[propKey] = await _resolveNode(value[propKey]);
            }
          }
          newMap[key] = newProps;
          continue;
        }

        if (key is String && key.startsWith('on')) {
          newMap[key] = value;
        } else {
          newMap[key] = await _resolveNode(value);
        }
      }
      return newMap;
    }

    if (node is YamlList) {
      final newList = <dynamic>[];
      for (final item in node) {
        newList.add(await _resolveNode(item));
      }
      return newList;
    }

    if (node is Map) {
      final newMap = <String, dynamic>{};
      for (final key in node.keys) {
        final value = node[key];
        if (key is String && key.startsWith('on')) {
          newMap[key] = value;
        } else {
          newMap[key] = await _resolveNode(value);
        }
      }
      return newMap;
    }

    if (node is List) {
      final newList = <dynamic>[];
      for (final item in node) {
        newList.add(await _resolveNode(item));
      }
      return newList;
    }

    return node;
  }
}
