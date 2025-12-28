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
    if (node is String && isShqlRef(node)) {
      final expression = parseShql(node).code;
      final result = await shql.eval(expression);
      return _resolveNode(result);
    }

    if (node is YamlMap) {
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

    if (node is YamlList) {
      final newList = <dynamic>[];
      for (final item in node) {
        newList.add(await _resolveNode(item));
      }
      return newList;
    }

    // This will handle non-YAML maps that might be returned from shql.eval
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

    // This will handle non-YAML lists that might be returned from shql.eval
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
