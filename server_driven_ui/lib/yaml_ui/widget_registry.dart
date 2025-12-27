import 'package:flutter/material.dart';

import 'package:server_driven_ui/yaml_ui/debouncer.dart';
import 'resolvers.dart';
import 'shql_bindings.dart';

typedef ChildBuilder = Widget Function(dynamic node, String path);

typedef WidgetFactory =
    Widget Function(
      BuildContext context,
      Map<String, dynamic> props,
      ChildBuilder buildChild,
      dynamic child,
      dynamic children,
      String path,
      ShqlBindings shql,
      Key key,
    );

class WidgetRegistry {
  final Map<String, WidgetFactory> _factories;

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
    'Spacer': _buildSpacer,
    'Text': _buildText,
    'ElevatedButton': _buildElevatedButton,
    'ListView': _buildListView,
    'TextField': _buildTextField,
    'Expanded': _buildExpanded,
    'Card': _buildCard,
  });

  WidgetFactory? get(String type) => _factories[type];

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
    // Create a key that is unique to the widget's path in the tree.
    final key = ValueKey<String>(path);
    return f(context, props, buildChild, child, children, path, shql, key);
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

Widget _buildScaffold(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  final appBarNode = props['appBar'];
  final bodyNode = props['body'];
  return Scaffold(
    key: key,
    appBar: appBarNode != null
        ? b(appBarNode, '$path.props.appBar') as PreferredSizeWidget
        : null,
    body: bodyNode != null ? b(bodyNode, '$path.props.body') : null,
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
  Key key,
) {
  final titleNode = props['title'] ?? child;
  return AppBar(
    key: key,
    title: titleNode != null ? b(titleNode, '$path.title') : null,
  );
}

Widget _buildCenter(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  return Center(
    key: key,
    child: child != null ? b(child, '$path.child') : null,
  );
}

Widget _buildColumn(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  if (children != null && children is! List) {
    return WidgetRegistry._error(
      context,
      'Invalid children for Column',
      'Expected a list, but got ${children.runtimeType} at $path',
    );
  }

  final childrenList = (children as List?) ?? [];

  return Column(
    key: key,
    mainAxisAlignment: Resolvers.mainAxis(
      props['mainAxisAlignment'] as String?,
    ),
    crossAxisAlignment: Resolvers.crossAxis(
      props['crossAxisAlignment'] as String?,
    ),
    children: childrenList
        .asMap()
        .entries
        .map((entry) => b(entry.value, '$path.children[${entry.key}]'))
        .toList(),
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
  Key key,
) {
  final list = (children is List) ? children : const [];
  return Row(
    key: key,
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
  Key key,
) {
  final childNode = props['child'] ?? child;
  return Padding(
    key: key,
    padding: Resolvers.edgeInsets(props['padding']),
    child: childNode != null ? b(childNode, '$path.child') : null,
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
  Key key,
) {
  return Container(
    key: key,
    decoration: BoxDecoration(color: Resolvers.color(props['color'])),
    width: (props['width'] as num?)?.toDouble(),
    height: (props['height'] as num?)?.toDouble(),
    padding: Resolvers.edgeInsets(props['padding']),
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
  Key key,
) {
  return SizedBox(
    key: key,
    width: (props['width'] is num) ? (props['width'] as num).toDouble() : null,
    height: (props['height'] is num)
        ? (props['height'] as num).toDouble()
        : null,
    child: child != null ? b(child, '$path.child') : null,
  );
}

Widget _buildSpacer(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  return Spacer(key: key);
}

Widget _buildText(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  final data = props['data'];
  final style = props['style'] as Map?;
  return Text(
    (data ?? '').toString(),
    key: key,
    style: TextStyle(
      color: Resolvers.color(style?['color']),
    ),
  );
}

Widget _buildElevatedButton(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  final childNode = props['child'] ?? child;
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (isShqlRef(onPressed)) {
    final callCode = stripPrefix(onPressed as String);
    cb = () {
      // Fire and forget; runtime is async. You can also await and show errors.
      shql.call(callCode);
    };
  }

  return ElevatedButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : const Text('Button'),
  );
}

Widget _buildExpanded(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  final childNode = props['child'] ?? child;
  return Expanded(
    key: key,
    child: childNode != null
        ? b(childNode, '$path.child')
        : const SizedBox.shrink(),
  );
}

Widget _buildCard(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  final childNode = props['child'] ?? child;
  return Card(
    key: key,
    color: Resolvers.color(props['color']),
    elevation: (props['elevation'] as num?)?.toDouble(),
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}

class _StatefulTextField extends StatefulWidget {
  const _StatefulTextField({
    required this.shql,
    this.onChanged,
    this.initialValue,
    this.decoration,
    super.key,
  });

  final ShqlBindings shql;
  final String? onChanged;
  final String? initialValue;
  final Map<String, dynamic>? decoration;

  @override
  State<_StatefulTextField> createState() => _StatefulTextFieldState();
}

class _StatefulTextFieldState extends State<_StatefulTextField> {
  late final TextEditingController _controller;
  late final Debouncer _debouncer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _debouncer = Debouncer(milliseconds: 500);
  }

  @override
  void didUpdateWidget(covariant _StatefulTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the initial value from the YAML changes, update the controller,
    // but only if the text is not the same as the user is currently editing.
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      // Using a post-frame callback to avoid conflicts with widget builds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.text = widget.initialValue ?? '';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final decoration = widget.decoration ?? {};

    return TextField(
      controller: _controller,
      onChanged: (value) {
        // When the user types, we use the debouncer to delay the shql call.
        if (isShqlRef(onChanged)) {
          _debouncer.run(() {
            final escapedValue = value.replaceAll("'", "''");
            final callCode = stripPrefix(
              onChanged as String,
            ).replaceAll('%', "'$escapedValue'");
            widget.shql.call(callCode).catchError((e) {
              debugPrint('Error in debounced onChanged: $e');
            });
          });
        }
      },
      decoration: InputDecoration(
        hintText: decoration['hintText']?.toString(),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

Widget _buildTextField(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  return _StatefulTextField(
    key: key,
    shql: shql,
    onChanged: props['onChanged'] as String?,
    initialValue: props['value'],
    decoration: props['decoration'] as Map<String, dynamic>?,
  );
}

Widget _buildListView(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
) {
  // By the time this factory is called, the engine has already resolved any
  // shql: expression for `children`. We can assume it's a List.
  if (children is! List) {
    return WidgetRegistry._error(
      context,
      'Invalid children for ListView',
      'Expected a list, but got ${children.runtimeType} at $path.children',
    );
  }

  final childrenList = children;
  return ListView.builder(
    key: key,
    itemCount: childrenList.length,
    itemBuilder: (BuildContext context, int i) {
      return b(childrenList[i], '$path.children[$i]');
    },
  );
}
