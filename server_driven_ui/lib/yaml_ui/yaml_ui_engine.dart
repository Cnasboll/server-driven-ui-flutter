import 'dart:async';

import 'package:flutter/material.dart';
import 'package:server_driven_ui/yaml_ui/resolvers.dart';
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
    final rootNode = (data is YamlMap && data.containsKey('screen'))
        ? data['screen']
        : data;
    return _resolveNode(rootNode);
  }

  /// Synchronously builds the widget tree from a fully resolved data structure.
  Widget build(dynamic resolvedData, BuildContext context) {
    return _buildNode(resolvedData, context, 'screen');
  }

  Widget _buildNode(dynamic node, BuildContext context, String path) {
    if (node is Map && node.containsKey('type')) {
      final type = node['type'] as String;
      final props = (node['props'] as Map?) ?? {};
      final child = node['child'];
      final children = node['children'];

      return registry.build(
        type: type,
        context: context,
        props: resolveMap(props, shql),
        buildChild: (node, childPath) => _buildNode(node, context, childPath),
        child: child,
        children: children,
        path: path,
        shql: shql,
      );
    }

    if (node is List) {
      return const SizedBox.shrink();
    }

    return Text(node?.toString() ?? 'null');
  }

  Future<dynamic> _resolveNode(dynamic node) async {
    if (node is String && node.startsWith('shql:')) {
      final expression = node.substring(5);
      final result = await shql.eval(expression);
      return _resolveNode(result);
    }
    if (node is Map) {
      final newMap = <String, dynamic>{};
      for (final key in node.keys) {
        if (key is String && key.startsWith('on')) {
          newMap[key] = node[key];
        } else {
          newMap[key] = await _resolveNode(node[key]);
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
