import 'package:flutter/material.dart';

import 'package:server_driven_ui/yaml_ui/debouncer.dart';
import 'package:server_driven_ui/yaml_ui/yaml_ui_engine.dart';
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
      YamlUiEngine engine,
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
    'SingleChildScrollView': _buildSingleChildScrollView,
    'TextField': _buildTextField,
    'Expanded': _buildExpanded,
    'Card': _buildCard,
    'Image': _buildImage,
    'ClipRRect': _buildClipRRect,
    'Observer': _buildObserver,
    'Stack': _buildStack,
    'Positioned': _buildPositioned,
    'CircularProgressIndicator': _buildCircularProgressIndicator,
    'LinearProgressIndicator': _buildLinearProgressIndicator,
    'Switch': _buildSwitch,
    'Checkbox': _buildCheckbox,
    'GridView': _buildGridView,
    'Wrap': _buildWrap,
    'Divider': _buildDivider,
    'ActionChip': _buildActionChip,
    'TextButton': _buildTextButton,
    'OutlinedButton': _buildOutlinedButton,
    'FilterChip': _buildFilterChip,
    'FilterEditor': _buildFilterEditor,
    'DropdownButton': _buildDropdownButton,
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
    required YamlUiEngine engine,
  }) {
    final f = _factories[type];
    if (f == null) {
      return _error(context, 'Unknown widget type: $type', 'Path: $path');
    }
    // Create a key that is unique to the widget's path in the tree.
    final key = ValueKey<String>(path);
    return f(
      context,
      props,
      buildChild,
      child,
      children,
      path,
      shql,
      key,
      engine,
    );
  }

  /// Calls a SHQL expression from a user-interaction callback (button press, tap, etc.).
  /// Catches any exception and shows it in a SnackBar rather than crashing the app.
  static void callShql(
    BuildContext context,
    ShqlBindings shql,
    String code, {
    bool targeted = false,
    Map<String, dynamic>? boundValues,
  }) {
    shql
        .call(code, targeted: targeted, boundValues: boundValues)
        .catchError((Object e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });
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
  YamlUiEngine engine,
) {
  final appBarNode = props['appBar'];
  final bodyNode = props['body'];
  final bottomNavNode = props['bottomNavigationBar'];
  return Scaffold(
    key: key,
    appBar: appBarNode != null
        ? b(appBarNode, '$path.props.appBar') as PreferredSizeWidget
        : null,
    body: bodyNode != null ? b(bodyNode, '$path.props.body') : null,
    bottomNavigationBar: bottomNavNode != null
        ? b(bottomNavNode, '$path.props.bottomNavigationBar')
        : null,
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
  YamlUiEngine engine,
) {
  final leadingNode = props['leading'];
  final titleNode = props['title'] ?? child;
  final actionsNode = props['actions'];
  List<Widget>? actions;
  if (actionsNode is List) {
    actions = actionsNode
        .asMap()
        .entries
        .map((e) => b(e.value, '$path.actions[${e.key}]'))
        .toList();
  }
  return AppBar(
    key: key,
    leading: leadingNode != null ? b(leadingNode, '$path.leading') : null,
    title: titleNode != null ? b(titleNode, '$path.title') : null,
    actions: actions,
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
  YamlUiEngine engine,
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
  YamlUiEngine engine,
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
  YamlUiEngine engine,
) {
  final childrenList = (children is List) ? children : [];

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
      for (var i = 0; i < childrenList.length; i++)
        b(childrenList[i], '$path.children[$i]'),
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
  YamlUiEngine engine,
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
  YamlUiEngine engine,
) {
  final decorationMap = props['decoration'] as Map?;
  final borderMap = decorationMap?['border'] as Map?;
  BoxBorder? border;
  if (borderMap != null) {
    border = Border.all(
      color: Resolvers.color(borderMap['color']) ?? Colors.black,
      width: (borderMap['width'] as num?)?.toDouble() ?? 1.0,
    );
  }

  return Container(
    key: key,
    width: (props['width'] as num?)?.toDouble(),
    height: (props['height'] as num?)?.toDouble(),
    padding: Resolvers.edgeInsets(props['padding']),
    margin: Resolvers.edgeInsets(props['margin']),
    alignment: Resolvers.alignment(props['alignment'] as String?),
    decoration: BoxDecoration(
      color: Resolvers.color(props['color'] ?? decorationMap?['color']),
      borderRadius: Resolvers.borderRadius(decorationMap?['borderRadius']),
      border: border,
    ),
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
  YamlUiEngine engine,
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
  YamlUiEngine engine,
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
  YamlUiEngine engine,
) {
  final data = props['data'];
  final style = props['style'] as Map?;
  final textAlign = Resolvers.textAlign(
    (props['textAlign'] ?? style?['textAlign']) as String?,
  );

  FontWeight? fontWeight;
  final fw = style?['fontWeight']?.toString();
  if (fw == 'bold' || fw == 'w700') {
    fontWeight = FontWeight.bold;
  } else if (fw == 'w500') {
    fontWeight = FontWeight.w500;
  } else if (fw == 'w600') {
    fontWeight = FontWeight.w600;
  } else if (fw == 'w400' || fw == 'normal') {
    fontWeight = FontWeight.normal;
  } else if (fw == 'w300') {
    fontWeight = FontWeight.w300;
  }

  return Text(
    (data ?? '').toString(),
    key: key,
    textAlign: textAlign,
    overflow: style?['overflow'] == 'ellipsis' ? TextOverflow.ellipsis : null,
    maxLines: (style?['maxLines'] as int?),
    style: TextStyle(
      color: Resolvers.color(style?['color']),
      fontSize: (style?['fontSize'] as num?)?.toDouble(),
      fontWeight: fontWeight,
      fontFamily: style?['fontFamily'] as String?,
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
  YamlUiEngine engine,
) {
  final childNode = props['child'] ?? child;
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (isShqlRef(onPressed)) {
    final (:code, :targeted) = parseShql(onPressed as String);
    cb = () {
      WidgetRegistry.callShql(context, shql, code, targeted: targeted);
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
  YamlUiEngine engine,
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
  YamlUiEngine engine,
) {
  final childNode = props['child'] ?? child;
  final onTap = props['onTap'];

  VoidCallback? cb;
  if (isShqlRef(onTap)) {
    final (:code, :targeted) = parseShql(onTap as String);
    cb = () {
      WidgetRegistry.callShql(context, shql, code, targeted: targeted);
    };
  }

  Widget card = Card(
    key: key,
    color: Resolvers.color(props['color']),
    elevation: (props['elevation'] as num?)?.toDouble(),
    child: childNode != null ? b(childNode, '$path.child') : null,
  );

  if (cb != null) {
    card = InkWell(onTap: cb, child: card);
  }

  return card;
}

Widget _buildClipRRect(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final childNode = props['child'] ?? child;
  return ClipRRect(
    key: key,
    borderRadius:
        Resolvers.borderRadius(props['borderRadius']) ?? BorderRadius.zero,
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}

Widget _buildImage(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final source = (props['source'] ?? props['src']) as String?;
  if (source == null) {
    return const SizedBox.shrink();
  }

  final width = (props['width'] as num?)?.toDouble();
  final height = (props['height'] as num?)?.toDouble();
  final fit = Resolvers.boxFit(props['fit'] as String?);

  if (source.startsWith('http')) {
    return Image.network(
      source,
      key: key,
      width: width,
      height: height,
      fit: fit,
    );
  } else {
    return Image.asset(
      source,
      key: key,
      width: width,
      height: height,
      fit: fit,
    );
  }
}

class _StatefulTextField extends StatefulWidget {
  const _StatefulTextField({
    required this.shql,
    this.onChanged,
    this.onSubmitted,
    this.initialValue,
    this.decoration,
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final String? onChanged;
  final String? onSubmitted;
  final String? initialValue;
  final Map<String, dynamic>? decoration;
  final YamlUiEngine engine;

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
        if (mounted) {
          _controller.text = widget.initialValue ?? '';
        }
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

    final onSubmitted = widget.onSubmitted;

    return TextField(
      controller: _controller,
      textInputAction: onSubmitted != null ? TextInputAction.done : null,
      onChanged: (value) {
        // When the user types, we use the debouncer to delay the shql call.
        if (isShqlRef(onChanged)) {
          _debouncer.run(() {
            var boundValues = {'value': value};
            final (:code, :targeted) = parseShql(onChanged as String);
            widget.shql
                .call(code, targeted: targeted, boundValues: boundValues)
                .catchError((e) {
                  debugPrint('Error in debounced onChanged: $e');
                });
          });
        }
      },
      onSubmitted: (value) {
        if (isShqlRef(onSubmitted)) {
          final (:code, :targeted) = parseShql(onSubmitted as String);
          widget.shql
              .call(code, targeted: targeted, boundValues: {'value': value})
              .catchError((e) {
                debugPrint('Error in onSubmitted: $e');
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
  YamlUiEngine engine,
) {
  return _StatefulTextField(
    key: key,
    shql: shql,
    onChanged: props['onChanged'] as String?,
    onSubmitted: props['onSubmitted'] as String?,
    initialValue: (props['value'] ?? props['initialValue'])?.toString(),
    decoration: props['decoration'] as Map<String, dynamic>?,
    engine: engine,
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
  YamlUiEngine engine,
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

Widget _buildSingleChildScrollView(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  if (child == null) {
    return WidgetRegistry._error(
      context,
      'SingleChildScrollView requires a child',
      path,
    );
  }

  return SingleChildScrollView(key: key, child: b(child, '$path.child'));
}

Widget _buildObserver(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final query = props['query'] as String?;
  final builder = props['builder'];

  if (query == null) {
    return WidgetRegistry._error(context, 'Observer requires a query', path);
  }
  if (builder == null) {
    return WidgetRegistry._error(context, 'Observer requires a builder', path);
  }

  return _Observer(
    key: key,
    shql: shql,
    query: query,
    builder: builder,
    buildChild: b,
    path: path,
    engine: engine,
  );
}

class _Observer extends StatefulWidget {
  const _Observer({
    required this.shql,
    required this.query,
    required this.builder,
    required this.buildChild,
    required this.path,
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final String query;
  final dynamic builder;
  final ChildBuilder buildChild;
  final String path;
  final YamlUiEngine engine;

  @override
  State<_Observer> createState() => _ObserverState();
}

class _ObserverState extends State<_Observer> {
  dynamic _resolvedBuilder;
  List<String> _queries = [];
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribeToQueries();
    // Initial resolution
    _resolveBuilder();
  }

  @override
  void didUpdateWidget(covariant _Observer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) {
      _unsubscribeFromQueries();
      _subscribeToQueries();
      _resolveBuilder();
    } else if (widget.builder != oldWidget.builder) {
      // If the builder template itself changes, re-resolve.
      _resolveBuilder();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromQueries();
    super.dispose();
  }

  void _subscribeToQueries() {
    _queries = widget.query
        .split(',')
        .map((q) => q.trim())
        .where((q) => q.isNotEmpty)
        .toList();
    for (final q in _queries) {
      widget.shql.addListener(q, _onDataChanged);
    }
  }

  void _unsubscribeFromQueries() {
    for (final q in _queries) {
      widget.shql.removeListener(q, _onDataChanged);
    }
    _queries = [];
  }

  void _onDataChanged() {
    // Data has changed, resolve the builder again and trigger a rebuild
    if (mounted) {
      _resolveBuilder();
    }
  }

  /// Whether [key] is an event-handler callback prop (e.g. onTap, onDelete,
  /// onToggleLock). These must NOT be eagerly evaluated — they run later when
  /// the user interacts with the widget. Matches the same convention used by
  /// YamlUiEngine._resolveNode: any key starting with "on" followed by an
  /// uppercase letter is a callback.
  static bool _isCallbackProp(String key) =>
      key.length > 2 && key.startsWith('on') && key[2] == key[2].toUpperCase();

  /// Recursively walks through the provided data structure and resolves any
  /// `shql:` expressions. This is the key to fixing the caching issue, as it
  /// forces re-evaluation outside of the engine's single-pass resolver.
  Future<dynamic> _recursivelyResolve(dynamic node) async {
    if (node is String && isShqlRef(node)) {
      final (:code, targeted: _) = parseShql(node);
      try {
        // The result of an expression could itself be a structure that needs resolving.
        final result = await widget.shql.eval(code);
        return await _recursivelyResolve(result);
      } catch (e) {
        debugPrint('Error evaluating shql in Observer: $e');
        return 'Error: $e';
      }
    }

    if (node is Map) {
      final newMap = <String, dynamic>{};
      for (final entry in node.entries) {
        // Skip callback props — they are evaluated at invocation time, not now.
        if (entry.key is String && _isCallbackProp(entry.key as String)) {
          newMap[entry.key] = entry.value;
        } else {
          newMap[entry.key] = await _recursivelyResolve(entry.value);
        }
      }
      return newMap;
    }

    if (node is List) {
      final newList = [];
      for (final item in node) {
        newList.add(await _recursivelyResolve(item));
      }
      return newList;
    }

    // Return primitives and other types as-is
    return node;
  }

  Future<void> _resolveBuilder() async {
    // Use the local, recursive resolver, NOT the engine's resolver.
    final generation = ++_resolveGeneration;
    final newResolvedBuilder = await _recursivelyResolve(widget.builder);
    // Discard stale results: only apply if this is still the latest resolve.
    if (mounted && generation == _resolveGeneration) {
      setState(() {
        _resolvedBuilder = newResolvedBuilder;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedBuilder == null) {
      // Initial loading state: show a small constrained spinner.
      // SizedBox bounds it so it never expands into unbounded space (e.g.,
      // when Observer is used as a trailing widget in ListTile/AppBar actions).
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    // The state change will naturally cause this to rebuild with new data.
    return widget.buildChild(_resolvedBuilder, '${widget.path}.builder');
  }
}

Widget _buildStack(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  if (children != null && children is! List) {
    return WidgetRegistry._error(
      context,
      'Invalid children for Stack',
      'Expected a list, but got ${children.runtimeType} at $path',
    );
  }

  final childrenList = (children as List?) ?? [];

  return Stack(
    key: key,
    alignment:
        Resolvers.alignment(props['alignment'] as String?) ??
        AlignmentDirectional.topStart,
    children: childrenList
        .asMap()
        .entries
        .map((entry) => b(entry.value, '$path.children[${entry.key}]'))
        .toList(),
  );
}

Widget _buildPositioned(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final childNode = props['child'] ?? child;
  return Positioned(
    key: key,
    top: (props['top'] as num?)?.toDouble(),
    right: (props['right'] as num?)?.toDouble(),
    bottom: (props['bottom'] as num?)?.toDouble(),
    left: (props['left'] as num?)?.toDouble(),
    child: childNode != null
        ? b(childNode, '$path.child')
        : const SizedBox.shrink(),
  );
}

Widget _buildCircularProgressIndicator(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  return CircularProgressIndicator(
    key: key,
    value: (props['value'] as num?)?.toDouble(),
    backgroundColor: Resolvers.color(props['backgroundColor']),
    color: Resolvers.color(props['color']),
    strokeWidth: (props['strokeWidth'] as num?)?.toDouble() ?? 4.0,
  );
}

class _StatefulSwitch extends StatefulWidget {
  const _StatefulSwitch({
    required this.shql,
    this.onChanged,
    this.value,
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final String? onChanged;
  final dynamic value;
  final YamlUiEngine engine;

  @override
  State<_StatefulSwitch> createState() => _StatefulSwitchState();
}

class _StatefulSwitchState extends State<_StatefulSwitch> {
  bool _currentValue = false;
  String? _valueBinding;

  @override
  void initState() {
    super.initState();
    _initializeValue();
  }

  void _initializeValue() {
    // Check if the value is a SHQL™ binding string
    if (widget.value is String && isShqlRef(widget.value as String)) {
      final (:code, targeted: _) = parseShql(widget.value as String);
      _valueBinding = code;
      widget.shql.addListener(_valueBinding!, _onDataChanged);
      // Immediately try to resolve the current value
      _resolveValue();
    } else if (widget.value is bool) {
      // Handle direct boolean value
      _currentValue = widget.value;
    }
  }

  Future<void> _resolveValue() async {
    if (_valueBinding == null) return;
    try {
      final result = await widget.shql.eval(_valueBinding!);
      if (mounted && result is bool) {
        setState(() {
          _currentValue = result;
        });
      }
    } catch (e) {
      debugPrint('Error resolving Switch value: $e');
    }
  }

  void _onDataChanged() {
    if (mounted) {
      _resolveValue();
    }
  }

  @override
  void didUpdateWidget(covariant _StatefulSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      // If the binding itself changes, remove old listener and set up new one
      if (_valueBinding != null) {
        widget.shql.removeListener(_valueBinding!, _onDataChanged);
      }
      _initializeValue();
    }
  }

  @override
  void dispose() {
    if (_valueBinding != null) {
      widget.shql.removeListener(_valueBinding!, _onDataChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    return Switch(
      value: _currentValue,
      onChanged: (newValue) {
        // Optimistically update the UI
        setState(() {
          _currentValue = newValue;
        });
        // Then notify the backend via SHQL™
        if (isShqlRef(onChanged)) {
          var boundValues = {'value': newValue};
          final (:code, :targeted) = parseShql(onChanged as String);
          widget.shql
              .call(code, targeted: targeted, boundValues: boundValues)
              .catchError((e) {
                debugPrint('Error in Switch onChanged: $e');
              });
        }
      },
    );
  }
}

Widget _buildSwitch(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  return _StatefulSwitch(
    key: key,
    shql: shql,
    onChanged: props['onChanged'] as String?,
    value: props['value'],
    engine: engine,
  );
}

class _StatefulCheckbox extends StatefulWidget {
  const _StatefulCheckbox({
    required this.shql,
    this.onChanged,
    this.value,
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final String? onChanged;
  final dynamic value;
  final YamlUiEngine engine;

  @override
  State<_StatefulCheckbox> createState() => _StatefulCheckboxState();
}

class _StatefulCheckboxState extends State<_StatefulCheckbox> {
  bool _currentValue = false;
  String? _valueBinding;

  @override
  void initState() {
    super.initState();
    _initializeValue();
  }

  void _initializeValue() {
    if (widget.value is String && isShqlRef(widget.value as String)) {
      final (:code, targeted: _) = parseShql(widget.value as String);
      _valueBinding = code;
      widget.shql.addListener(_valueBinding!, _onDataChanged);
      _resolveValue();
    } else if (widget.value is bool) {
      _currentValue = widget.value;
    }
  }

  Future<void> _resolveValue() async {
    if (_valueBinding == null) return;
    try {
      final result = await widget.shql.eval(_valueBinding!);
      if (mounted && result is bool) {
        setState(() {
          _currentValue = result;
        });
      }
    } catch (e) {
      debugPrint('Error resolving Checkbox value: $e');
    }
  }

  void _onDataChanged() {
    if (mounted) {
      _resolveValue();
    }
  }

  @override
  void didUpdateWidget(covariant _StatefulCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (_valueBinding != null) {
        widget.shql.removeListener(_valueBinding!, _onDataChanged);
      }
      _initializeValue();
    }
  }

  @override
  void dispose() {
    if (_valueBinding != null) {
      widget.shql.removeListener(_valueBinding!, _onDataChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    return Checkbox(
      value: _currentValue,
      onChanged: (newValue) {
        if (newValue == null) return;
        setState(() {
          _currentValue = newValue;
        });
        if (isShqlRef(onChanged)) {
          var boundValues = {'value': newValue};
          final (:code, :targeted) = parseShql(onChanged as String);
          widget.shql
              .call(code, targeted: targeted, boundValues: boundValues)
              .catchError((e) {
                debugPrint('Error in Checkbox onChanged: $e');
              });
        }
      },
    );
  }
}

Widget _buildCheckbox(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  return _StatefulCheckbox(
    key: key,
    shql: shql,
    onChanged: props['onChanged'] as String?,
    value: props['value'],
    engine: engine,
  );
}

Widget _buildGridView(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  if (children is! List) {
    return WidgetRegistry._error(
      context,
      'Invalid children for GridView',
      'Expected a list, but got ${children.runtimeType} at $path',
    );
  }

  final childrenList = children;
  final baseCrossAxisCount = (props['crossAxisCount'] as int?) ?? 2;
  final childAspectRatio =
      (props['childAspectRatio'] as num?)?.toDouble() ?? 1.0;
  final crossAxisSpacing =
      (props['crossAxisSpacing'] as num?)?.toDouble() ?? 0.0;
  final mainAxisSpacing =
      (props['mainAxisSpacing'] as num?)?.toDouble() ?? 0.0;
  final padding = Resolvers.edgeInsets(props['padding']);

  // Dynamic scaling: use LayoutBuilder to adapt columns to screen width
  return LayoutBuilder(
    key: key,
    builder: (context, constraints) {
      // ~180 dp per column; never go below the YAML-specified base count
      final columns = (constraints.maxWidth / 180).floor().clamp(baseCrossAxisCount, 6);
      return GridView.count(
        crossAxisCount: columns,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        padding: padding,
        children: childrenList
            .asMap()
            .entries
            .map((entry) => b(entry.value, '$path.children[${entry.key}]'))
            .toList(),
      );
    },
  );
}

Widget _buildLinearProgressIndicator(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  return LinearProgressIndicator(
    key: key,
    value: (props['value'] as num?)?.toDouble(),
    backgroundColor: Resolvers.color(props['backgroundColor']),
    color: Resolvers.color(props['color']),
  );
}

Widget _buildWrap(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final childrenList = (children is List) ? children : [];
  return Wrap(
    key: key,
    spacing: (props['spacing'] as num?)?.toDouble() ?? 0.0,
    runSpacing: (props['runSpacing'] as num?)?.toDouble() ?? 0.0,
    children: childrenList
        .asMap()
        .entries
        .map((entry) => b(entry.value, '$path.children[${entry.key}]'))
        .toList(),
  );
}

Widget _buildDivider(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  return Divider(
    key: key,
    height: (props['height'] as num?)?.toDouble(),
    thickness: (props['thickness'] as num?)?.toDouble(),
    color: Resolvers.color(props['color']),
  );
}

Widget _buildActionChip(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final label = props['label']?.toString() ?? '';
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (isShqlRef(onPressed)) {
    final (:code, :targeted) = parseShql(onPressed as String);
    cb = () => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
  }

  return ActionChip(
    key: key,
    label: Text(label),
    onPressed: cb,
  );
}

Widget _buildTextButton(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final childNode = props['child'] ?? child;
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (isShqlRef(onPressed)) {
    final (:code, :targeted) = parseShql(onPressed as String);
    cb = () => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
  }

  return TextButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : const Text('Button'),
  );
}

Widget _buildOutlinedButton(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final childNode = props['child'] ?? child;
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (isShqlRef(onPressed)) {
    final (:code, :targeted) = parseShql(onPressed as String);
    cb = () => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
  }

  return OutlinedButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : const Text('Button'),
  );
}

Widget _buildFilterChip(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final label = props['label']?.toString() ?? '';
  final selected = props['selected'] == true;
  final onSelected = props['onSelected'];

  void Function(bool)? cb;
  if (isShqlRef(onSelected)) {
    final (:code, :targeted) = parseShql(onSelected as String);
    cb = (_) => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
  }

  return FilterChip(
    key: key,
    label: Text(label),
    selected: selected,
    onSelected: cb,
  );
}

// ---------------------------------------------------------------------------
// FilterEditor — reusable filter management widget
// ---------------------------------------------------------------------------

Widget _buildFilterEditor(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  final mode = props['mode']?.toString() ?? 'manage';
  final onSelect = props['onSelect']?.toString();
  return _FilterEditor(key: key, shql: shql, mode: mode, onSelect: onSelect);
}

class _FilterEditor extends StatefulWidget {
  const _FilterEditor({
    required this.shql,
    required this.mode,
    this.onSelect,
    super.key,
  });

  final ShqlBindings shql;
  final String mode; // 'manage' or 'apply'
  final String? onSelect; // SHQL™ expression to run after selecting a filter

  @override
  State<_FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<_FilterEditor> {
  List<Map<String, dynamic>> _filters = [];
  List _filterCounts = [];
  int _activeFilterIndex = -1;
  int _editingIndex = -1;
  int _totalHeroes = 0;
  bool _compiling = false;
  bool _filtering = false;

  late final TextEditingController _queryController;
  late final TextEditingController _nameController;
  late final Debouncer _debouncer;
  final ScrollController _scrollController = ScrollController();

  bool get _isApplyMode => widget.mode == 'apply';

  // ---- lifecycle ----

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _nameController = TextEditingController();
    _debouncer = Debouncer(milliseconds: 500);
    _subscribe();
    _readVariables();
  }

  @override
  void dispose() {
    _unsubscribe();
    _queryController.dispose();
    _nameController.dispose();
    _debouncer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribe() {
    for (final v in _watchedVars) {
      widget.shql.addListener(v, _onDataChanged);
    }
  }

  void _unsubscribe() {
    for (final v in _watchedVars) {
      widget.shql.removeListener(v, _onDataChanged);
    }
  }

  static const _watchedVars = [
    '_filters',
    '_filter_counts',
    '_active_filter_index',
    '_current_query',
    '_heroes',
    '_filters_compiling',
    '_filtering',
  ];

  void _onDataChanged() {
    if (!mounted) return;
    _readVariables();
  }

  void _readVariables() {
    setState(() {
      final rawFilters = _getList('_filters');
      _filters = rawFilters.map((f) => widget.shql.objectToMap(f)).toList();
      _filterCounts = _getList('_filter_counts');
      _activeFilterIndex = _getInt('_active_filter_index', -1);
      final heroes = widget.shql.getVariable('_heroes');
      _totalHeroes = heroes is Map ? heroes.length : heroes is List ? heroes.length : 0;
      _compiling = widget.shql.getVariable('_filters_compiling') == true;
      _filtering = widget.shql.getVariable('_filtering') == true;

      // In apply mode, show the active filter's predicate (read-only hint of
      // what the filter does) or the free-form query text if no filter is active.
      if (_isApplyMode) {
        final query = (widget.shql.getVariable('_current_query') ?? '').toString();
        _editingIndex = -1;
        if (query.isNotEmpty) {
          _setControllerText(query);
        } else if (_activeFilterIndex >= 0 && _activeFilterIndex < _filters.length) {
          _setControllerText(
            _filters[_activeFilterIndex]['predicate']?.toString() ?? '',
          );
        } else {
          _setControllerText('');
        }
      }
    });
  }

  List _getList(String name) {
    final v = widget.shql.getVariable(name);
    return v is List ? List.from(v) : [];
  }

  int _getInt(String name, int fallback) {
    final v = widget.shql.getVariable(name);
    return v is int ? v : fallback;
  }

  /// Update controller only when value actually differs from what's shown,
  /// so we never fight with the user's cursor position.
  void _setControllerText(String text) {
    if (_queryController.text != text) {
      _queryController.text = text;
    }
  }

  // ---- actions ----

  void _selectChip(int index) {
    setState(() => _editingIndex = index);
    if (index >= 0 && index < _filters.length) {
      if (!_isApplyMode) {
        _queryController.text =
            _filters[index]['predicate']?.toString() ?? '';
      }
      _nameController.text = _filters[index]['name']?.toString() ?? '';
    }
    if (_isApplyMode) {
      widget.shql.call('APPLY_FILTER($index)', targeted: true);
      if (widget.onSelect != null) {
        widget.shql.call(widget.onSelect!, targeted: true);
      }
    }
  }

  void _selectAll() {
    setState(() => _editingIndex = -1);
    _queryController.clear();
    widget.shql.call('APPLY_FILTER(-1)', targeted: true);
    widget.shql.call("APPLY_QUERY('')", targeted: true);
  }

  void _onQuerySubmitted(String value) {
    if (_isApplyMode) {
      // In apply mode, the query field is always a free-form search
      widget.shql.call(
        'APPLY_QUERY(value)',
        targeted: true,
        boundValues: {'value': value},
      );
      if (widget.onSelect != null) {
        widget.shql.call(widget.onSelect!, targeted: true);
      }
    } else if (_editingIndex >= 0 && _editingIndex < _filters.length) {
      // In edit/manage mode, save the predicate for the selected filter
      widget.shql.call(
        'SAVE_FILTER(name, value)',
        targeted: true,
        boundValues: {
          'name': _filters[_editingIndex]['name']?.toString() ?? '',
          'value': value,
        },
      );
    }
  }

  void _onNameSubmitted(String value) {
    if (_editingIndex >= 0 && _editingIndex < _filters.length) {
      widget.shql.call(
        'RENAME_FILTER(index, name)',
        targeted: true,
        boundValues: {'index': _editingIndex, 'name': value},
      );
    }
  }

  void _addFilter() {
    widget.shql.call('ADD_FILTER()');
    // Scroll to the bottom after the new filter is added and the list rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _deleteFilter() {
    if (_editingIndex >= 0) {
      final idx = _editingIndex;
      setState(() => _editingIndex = -1);
      _queryController.clear();
      widget.shql.call('DELETE_FILTER($idx)');
    }
  }

  void _resetFilters() {
    setState(() => _editingIndex = -1);
    _queryController.clear();
    widget.shql.call('RESET_PREDICATES()');
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Filter list (scrollable box) --
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView(
            controller: _scrollController,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (_isApplyMode)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.select_all, size: 20),
                  title: const Text('All'),
                  trailing: Text(
                    '$_totalHeroes',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  selected: _activeFilterIndex == -1 && _editingIndex == -1,
                  onTap: () => _selectAll(),
                ),
              for (int i = 0; i < _filters.length; i++)
                ListTile(
                  dense: true,
                  leading: Icon(
                    _isApplyMode && _activeFilterIndex == i
                        ? Icons.check_circle
                        : Icons.filter_list,
                    size: 20,
                  ),
                  title: Text(_filters[i]['name']?.toString() ?? 'Unnamed'),
                  trailing: Text(
                    i < _filterCounts.length ? '${_filterCounts[i]}' : '',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  selected: _isApplyMode
                      ? _activeFilterIndex == i
                      : _editingIndex == i,
                  onTap: _compiling || _filtering ? null : () => _selectChip(i),
                ),
            ],
          ),
        ),

        // -- Selected filter detail --
        if (_editingIndex >= 0 && _editingIndex < _filters.length) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _onNameSubmitted(_nameController.text);
              },
              child: TextField(
                controller: _nameController,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: 'Filter name',
                  isDense: true,
                  border: InputBorder.none,
                ),
                onSubmitted: _onNameSubmitted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _buildQueryField(),
        ] else if (_isApplyMode) ...[
          // No filter selected — free-form query
          _buildQueryField(),
        ],

        // -- Action buttons --
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Filter'),
                onPressed: _addFilter,
              ),
              if (_editingIndex >= 0)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  onPressed: _deleteFilter,
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Reset Defaults'),
                onPressed: _compiling || _filtering ? null : _resetFilters,
              ),
            ],
          ),
        ),
        if (_compiling || _filtering)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(
                  _compiling ? 'Compiling filters...' : 'Applying filter...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQueryField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _queryController,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: _isApplyMode
              ? 'SHQL™ expression or plaintext search'
              : 'SHQL™ predicate expression',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_isApplyMode ? Icons.play_arrow : Icons.save),
            tooltip: _isApplyMode ? 'Apply query' : 'Save filter',
            onPressed: () => _onQuerySubmitted(_queryController.text),
          ),
        ),
        onChanged: _onQueryChanged,
        onSubmitted: _onQuerySubmitted,
      ),
    );
  }

  /// Debounced handler: in apply mode always applies a free-form query;
  /// in edit/manage mode saves the filter's predicate.
  void _onQueryChanged(String value) {
    _debouncer.run(() {
      if (_isApplyMode) {
        widget.shql.call(
          'APPLY_QUERY(value)',
          targeted: true,
          boundValues: {'value': value},
        );
      } else if (_editingIndex >= 0 && _editingIndex < _filters.length) {
        // Update the named filter's predicate and keep it selected
        final name = _filters[_editingIndex]['name']?.toString() ?? '';
        widget.shql.call(
          'SAVE_FILTER(name, value)',
          targeted: true,
          boundValues: {'name': name, 'value': value},
        );
      }
    });
  }
}

// --- DropdownButton ---

Widget _buildDropdownButton(
  BuildContext context,
  Map<String, dynamic> props,
  ChildBuilder b,
  dynamic child,
  dynamic children,
  String path,
  ShqlBindings shql,
  Key key,
  YamlUiEngine engine,
) {
  return _StatefulDropdown(
    key: key,
    shql: shql,
    items: props['items'],
    value: props['value'],
    onChanged: props['onChanged'] as String?,
    hint: props['hint'] as String?,
    engine: engine,
  );
}

class _StatefulDropdown extends StatefulWidget {
  const _StatefulDropdown({
    required this.shql,
    required this.items,
    this.value,
    this.onChanged,
    this.hint,
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final dynamic items;
  final dynamic value;
  final String? onChanged;
  final String? hint;
  final YamlUiEngine engine;

  @override
  State<_StatefulDropdown> createState() => _StatefulDropdownState();
}

class _StatefulDropdownState extends State<_StatefulDropdown> {
  String? _currentValue;
  List<String> _items = [];
  String? _valueBinding;
  String? _itemsBinding;

  @override
  void initState() {
    super.initState();
    _initializeItems();
    _initializeValue();
  }

  void _initializeItems() {
    if (widget.items is String && isShqlRef(widget.items as String)) {
      final (:code, targeted: _) = parseShql(widget.items as String);
      _itemsBinding = code;
      widget.shql.addListener(_itemsBinding!, _onItemsChanged);
      _resolveItems();
    } else if (widget.items is List) {
      _items = (widget.items as List).map((e) => e.toString()).toList();
    }
  }

  void _initializeValue() {
    if (widget.value is String && isShqlRef(widget.value as String)) {
      final (:code, targeted: _) = parseShql(widget.value as String);
      _valueBinding = code;
      widget.shql.addListener(_valueBinding!, _onValueChanged);
      _resolveValue();
    } else if (widget.value != null) {
      _currentValue = widget.value.toString();
    }
  }

  Future<void> _resolveItems() async {
    if (_itemsBinding == null) return;
    try {
      final result = await widget.shql.eval(_itemsBinding!);
      if (mounted && result is List) {
        setState(() {
          _items = result.map((e) => e.toString()).toList();
        });
      }
    } catch (e) {
      debugPrint('Error resolving DropdownButton items: $e');
    }
  }

  Future<void> _resolveValue() async {
    if (_valueBinding == null) return;
    try {
      final result = await widget.shql.eval(_valueBinding!);
      if (mounted) {
        setState(() {
          _currentValue = result?.toString();
        });
      }
    } catch (e) {
      debugPrint('Error resolving DropdownButton value: $e');
    }
  }

  void _onItemsChanged() {
    if (mounted) _resolveItems();
  }

  void _onValueChanged() {
    if (mounted) _resolveValue();
  }

  @override
  void didUpdateWidget(covariant _StatefulDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      if (_itemsBinding != null) {
        widget.shql.removeListener(_itemsBinding!, _onItemsChanged);
      }
      _initializeItems();
    }
    if (widget.value != oldWidget.value) {
      if (_valueBinding != null) {
        widget.shql.removeListener(_valueBinding!, _onValueChanged);
      }
      _initializeValue();
    }
  }

  @override
  void dispose() {
    if (_itemsBinding != null) {
      widget.shql.removeListener(_itemsBinding!, _onItemsChanged);
    }
    if (_valueBinding != null) {
      widget.shql.removeListener(_valueBinding!, _onValueChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: (_currentValue != null && _items.contains(_currentValue))
          ? _currentValue
          : null,
      hint: widget.hint != null ? Text(widget.hint!) : null,
      isExpanded: true,
      items: _items
          .map((item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              ))
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _currentValue = value;
        });
        if (widget.onChanged != null) {
          widget.shql.call(
            widget.onChanged!,
            targeted: true,
            boundValues: {'value': value},
          );
        }
      },
    );
  }
}
