import 'dart:async';
import 'package:flutter/material.dart';
import 'package:server_driven_ui/yaml_ui/shql_bindings.dart';
import 'package:server_driven_ui/yaml_ui/widget_registry.dart';
import 'package:yaml/yaml.dart';

typedef ErrorWidgetBuilder = Widget Function(String title, String details);

class YamlUiEngine {
  final WidgetRegistry registry;
  final ShqlBindings shql;
  final ErrorWidgetBuilder onErrorWidget;

  // Cache for stream controllers to avoid creating new streams on every build.
  final Map<String, StreamController<dynamic>> _streamControllers = {};

  YamlUiEngine({
    required this.registry,
    required this.shql,
    required this.onErrorWidget,
  }) {
    // When SHQL state mutates, re-evaluate all expressions and push to streams.
    shql.onMutated = () {
      _streamControllers.forEach((expression, controller) {
        shql.eval(expression).then((value) {
          if (!controller.isClosed) {
            controller.add(value);
          }
        });
      });
    };
  }

  // Dispose method to close all stream controllers and prevent memory leaks.
  void dispose() {
    for (var controller in _streamControllers.values) {
      controller.close();
    }
    _streamControllers.clear();
  }

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

  bool isShqlRef(dynamic value) => value is String && value.startsWith('shql:');
  String stripPrefix(String value) => value.substring('shql:'.length);

  Widget buildNode(dynamic node, BuildContext context, {required String path}) {
    try {
      if (node == null) {
        return const SizedBox.shrink();
      }
      final n = _normalize(node);

      if (n is Map) {
        final nodeMap = n.map((key, value) => MapEntry(key.toString(), value));
        final type = nodeMap['type']?.toString();
        if (type == null) {
          return onErrorWidget('Missing "type"', 'Path: $path');
        }

        final props = (nodeMap['props'] is Map)
            ? Map<String, dynamic>.from(nodeMap['props'] as Map)
            : <String, dynamic>{};
        final child = nodeMap.containsKey('child') ? nodeMap['child'] : null;
        final children = nodeMap['children'];

        // If children is a SHQL expression, use a StreamBuilder.
        if (isShqlRef(children)) {
          final expression = stripPrefix(children as String);
          final controller = _streamControllers.putIfAbsent(expression, () {
            final c = StreamController<dynamic>.broadcast();
            // Initial data load
            shql
                .eval(expression)
                .then((value) {
                  if (!c.isClosed) c.add(value);
                })
                .catchError((e, st) {
                  if (!c.isClosed) c.addError(e, st);
                });
            return c;
          });

          return StreamBuilder(
            stream: controller.stream,
            builder: (ctx, snap) {
              if (snap.hasError) {
                return onErrorWidget(
                  'SHQL children error',
                  '${snap.error}\n\n${snap.stackTrace}',
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return registry.build(
                type: type,
                context: context,
                props: props,
                buildChild: (dyn, childPath) =>
                    buildNode(dyn, context, path: childPath),
                child: child,
                children: snap.data,
                path: path,
                shql: shql,
              );
            },
          );
        }

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
