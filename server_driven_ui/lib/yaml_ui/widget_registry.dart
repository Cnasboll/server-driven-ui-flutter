import 'package:flutter/material.dart';

import 'resolvers.dart';
import 'shql_bindings.dart';

typedef ChildBuilder = Widget Function(dynamic node, String path);

class WidgetRegistry {
  final Map<String, _WidgetFactory> _factories;

  WidgetRegistry(this._factories);

  factory WidgetRegistry.basic() => WidgetRegistry({
    'Scaffold': _buildScaffold,
    'AppBar': _buildAppBar,
    'Center': _buildCenter,
    'Column': _buildColumn,
    'Row': _buildRow,
    'Padding': _buildPadding,
    'Container': _buildContainer,
    'SizedBox': _buildSizedBox,
    'Text': _buildText,
    'ElevatedButton': _buildElevatedButton,
  });

  Widget build({
    required String type,
    required BuildContext context,
    required Map<String, dynamic> props,
    required ChildBuilder buildChild,
    required dynamic child,
    required dynamic children,
    required String path,
    required ShqlBindings shql,
  }) {
    final f = _factories[type];
    if (f == null) {
      return _error(context, 'Unknown widget type: $type', 'Path: $path');
    }
    return f(context, props, buildChild, child, children, path, shql);
  }

  static Widget _error(BuildContext context, String title, String details) {
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

typedef _WidgetFactory =
    Widget Function(
      BuildContext context,
      Map<String, dynamic> props,
      ChildBuilder buildChild,
      dynamic child,
      dynamic children,
      String path,
      ShqlBindings shql,
    );

Widget _buildScaffold(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  final appBarNode = props['appBar'];
  final bodyNode = props['body'] ?? child;
  return Scaffold(
    appBar: appBarNode != null
        ? b(appBarNode, '$path.props.appBar') as PreferredSizeWidget
        : null,
    body: bodyNode != null ? b(bodyNode, '$path.body') : null,
  );
}

Widget _buildAppBar(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  final titleNode = props['title'] ?? child;
  return AppBar(title: titleNode != null ? b(titleNode, '$path.title') : null);
}

Widget _buildCenter(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  return Center(child: child != null ? b(child, '$path.child') : null);
}

Widget _buildColumn(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  final list = (children is List) ? children : const [];
  return Column(
    mainAxisAlignment: Resolvers.mainAxis(
      props['mainAxisAlignment']?.toString(),
      fallback: MainAxisAlignment.start,
    ),
    crossAxisAlignment: Resolvers.crossAxis(
      props['crossAxisAlignment']?.toString(),
      fallback: CrossAxisAlignment.center,
    ),
    mainAxisSize: (props['mainAxisSize']?.toString().toLowerCase() == 'min')
        ? MainAxisSize.min
        : MainAxisSize.max,
    children: [
      for (var i = 0; i < list.length; i++) b(list[i], '$path.children[$i]'),
    ],
  );
}

Widget _buildRow(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  final list = (children is List) ? children : const [];
  return Row(
    mainAxisAlignment: Resolvers.mainAxis(
      props['mainAxisAlignment']?.toString(),
      fallback: MainAxisAlignment.start,
    ),
    crossAxisAlignment: Resolvers.crossAxis(
      props['crossAxisAlignment']?.toString(),
      fallback: CrossAxisAlignment.center,
    ),
    mainAxisSize: (props['mainAxisSize']?.toString().toLowerCase() == 'min')
        ? MainAxisSize.min
        : MainAxisSize.max,
    children: [
      for (var i = 0; i < list.length; i++) b(list[i], '$path.children[$i]'),
    ],
  );
}

Widget _buildPadding(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  return Padding(
    padding: Resolvers.edgeInsets(props['padding']),
    child: child != null ? b(child, '$path.child') : null,
  );
}

Widget _buildContainer(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  return Container(
    padding: Resolvers.edgeInsets(props['padding']),
    margin: Resolvers.edgeInsets(props['margin']),
    color: Resolvers.color(props['color']),
    child: child != null ? b(child, '$path.child') : null,
  );
}

Widget _buildSizedBox(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  return SizedBox(
    width: (props['width'] is num) ? (props['width'] as num).toDouble() : null,
    height: (props['height'] is num)
        ? (props['height'] as num).toDouble()
        : null,
    child: child != null ? b(child, '$path.child') : null,
  );
}

Widget _buildText(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  final data = props['data'];
  // Support: data: "literal" OR data: "expr: someFunc()"
  if (isExprRef(data)) {
    final expr = stripPrefix(data as String);
    return _AsyncText(expr: expr, shql: shql);
  }
  return Text((data ?? '').toString());
}

Widget _buildElevatedButton(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
) {
  final childNode = props['child'] ?? child;
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (isCallRef(onPressed)) {
    final callCode = stripPrefix(onPressed as String);
    cb = () {
      // Fire and forget; runtime is async. You can also await and show errors.
      shql.call(callCode);
    };
  }

  return ElevatedButton(
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : const Text('Button'),
  );
}

/// A tiny async binding widget. Evaluates SHQL each build (OK for demos).
/// If you want: cache per-frame or per-variable dependency later.
class _AsyncText extends StatelessWidget {
  final String expr;
  final ShqlBindings shql;
  const _AsyncText({required this.expr, required this.shql});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: shql.eval(expr),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Text('…');
        }
        if (snap.hasError) return Text('ERR: ${snap.error}');
        return Text((snap.data ?? '').toString());
      },
    );
  }
}
