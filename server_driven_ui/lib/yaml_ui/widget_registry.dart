import 'package:flutter/material.dart';

import 'package:server_driven_ui/yaml_ui/animated_number.dart';
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
    'DropdownButton': _buildDropdownButton,
    'Icon': _buildIcon,
    'IconButton': _buildIconButton,
    'SafeArea': _buildSafeArea,
    'ListTile': _buildListTile,
    'BottomNavigationBar': _buildBottomNavigationBar,
    'AnimatedNumber': _buildAnimatedNumber,
    'FilledButton': _buildFilledButton,
    'AlertDialog': _buildAlertDialog,
    'CheckboxListTile': _buildCheckboxListTile,
    'ConstrainedBox': _buildConstrainedBox,
    'InkWell': _buildInkWell,
    'Material': _buildMaterial,
    'Dismissible': _buildDismissible,
    'Semantics': _buildSemantics,
    'Tooltip': _buildTooltip,
  });

  WidgetFactory? get(String type) => _factories[type];

  /// Register a YAML-defined widget template under [name].
  ///
  /// The [template] is a parsed YAML map (e.g. `{type: Column, props: ...}`).
  /// Any string value starting with `"prop:"` is substituted with the caller's
  /// props at build time. For example, `"prop:label"` becomes `props['label']`.
  void registerTemplate(String name, dynamic template) {
    _factories[name] = (context, props, buildChild, child, children, path, shql, key, engine) {
      final resolved = substituteProps(template, props);
      return buildChild(resolved, '$path.$name');
    };
  }

  /// Deep-walks [node], replacing `"prop:xyz"` strings with `props['xyz']`.
  ///
  /// When an `on*` key (callback) resolves to a raw string without a `shql:`
  /// prefix, it is automatically wrapped as `"shql: <expr>"` so the framework
  /// recognises it as a SHQL™ callback. Callbacks are always SHQL™ — no other
  /// abstraction is supported.
  static dynamic substituteProps(dynamic node, Map<String, dynamic> props) {
    if (node is String && node.startsWith('prop:')) {
      return props[node.substring(5)];
    }
    if (node is Map) {
      return node.map((k, v) {
        final resolved = substituteProps(v, props);
        // on* keys are always SHQL™ callbacks — auto-prefix if needed.
        if (resolved is String &&
            !isShqlRef(resolved) &&
            k is String &&
            k.length > 2 && k.startsWith('on') && k[2] == k[2].toUpperCase()) {
          return MapEntry(k, 'shql: $resolved');
        }
        return MapEntry(k, resolved);
      });
    }
    if (node is List) {
      return node.map((item) => substituteProps(item, props)).toList();
    }
    return node;
  }

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

  /// A shared basic registry + lightweight SHQL™ bindings for static widget construction.
  static final WidgetRegistry _basicInstance = WidgetRegistry.basic();
  static late ShqlBindings _staticShql;
  static late YamlUiEngine _staticEngine;
  static bool _staticInitialized = false;

  /// Initialize the static SHQL™ bindings with platform boundaries.
  /// Must be called once at startup before [buildStatic] or [staticShql] are used.
  /// All parameters are forwarded to the [ShqlBindings] constructor.
  static void initStaticBindings({
    VoidCallback? onMutated,
    Function(dynamic value)? printLine,
    Future<String?> Function()? readline,
    Future<String?> Function(String prompt)? prompt,
    Future<void> Function(String routeName)? navigate,
    Future<dynamic> Function(String url)? fetch,
    Future<dynamic> Function(String url, dynamic body)? post,
    Future<dynamic> Function(String url, dynamic body)? patch,
    Future<dynamic> Function(String url, String token)? fetchAuth,
    Future<dynamic> Function(String url, dynamic body, String token)? patchAuth,
    Future<void> Function(String key, dynamic value)? saveState,
    Future<dynamic> Function(String key, dynamic defaultValue)? loadState,
    Function(String message)? debugLog,
    Map<String, Function()>? nullaryFunctions,
    Map<String, Function(dynamic)>? unaryFunctions,
    Map<String, Function(dynamic, dynamic)>? binaryFunctions,
    Map<String, Function(dynamic, dynamic, dynamic)>? ternaryFunctions,
  }) {
    _staticShql = ShqlBindings(
      onMutated: onMutated ?? () {},
      printLine: printLine,
      readline: readline,
      prompt: prompt,
      navigate: navigate,
      fetch: fetch,
      post: post,
      patch: patch,
      fetchAuth: fetchAuth,
      patchAuth: patchAuth,
      saveState: saveState,
      loadState: loadState,
      debugLog: debugLog,
      nullaryFunctions: nullaryFunctions,
      unaryFunctions: unaryFunctions,
      binaryFunctions: binaryFunctions,
      ternaryFunctions: ternaryFunctions,
    );
    _staticEngine = YamlUiEngine(_staticShql, _basicInstance);
    _staticInitialized = true;
  }

  /// Public access to the static SHQL™ bindings — for setting dialog variables
  /// (e.g. `_DIALOG_TEXT`, `_APPLY_TO_ALL`) before showing YAML-driven dialogs.
  static ShqlBindings get staticShql {
    assert(_staticInitialized, 'Call WidgetRegistry.initStaticBindings() before accessing staticShql.');
    return _staticShql;
  }

  /// Register a custom Dart [WidgetFactory] on the static registry so it is
  /// available to [buildStatic] (imperative screens, dialogs, etc.).
  static void registerStaticFactory(String name, WidgetFactory factory) {
    _basicInstance._factories[name] = factory;
  }

  /// Register a YAML-defined widget template on the static registry so it is
  /// available to [buildStatic] (imperative screens, dialogs, etc.).
  static void registerStaticTemplate(String name, dynamic template) {
    _basicInstance.registerTemplate(name, template);
  }

  /// Load and register a YAML template string on the static registry.
  static void loadStaticTemplate(String name, String yaml) {
    _staticEngine.loadWidgetTemplate(name, yaml);
  }

  /// Build a widget from a YAML-like node spec without requiring a running
  /// SHQL™ engine. Useful for imperative screens (login, splash, dialogs)
  /// that still want registry-driven leaf construction.
  ///
  /// The [node] is a map like `{'type': 'Text', 'props': {'data': 'Hello'}}`.
  /// Nested children are resolved recursively through the same registry.
  static Widget buildStatic(BuildContext context, dynamic node, [String path = 'static']) {
    // Pass through pre-built Widget objects unchanged
    if (node is Widget) return node;
    if (node is! Map) {
      return const SizedBox.shrink();
    }
    final type = node['type'] as String?;
    if (type == null) return const SizedBox.shrink();
    final props = (node['props'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final child = node['child'] ?? props['child'];
    final children = node['children'] ?? props['children'];
    return _basicInstance.build(
      type: type,
      context: context,
      props: props,
      buildChild: (childNode, childPath) => buildStatic(context, childNode, childPath),
      child: child,
      children: children,
      path: path,
      shql: _staticShql,
      engine: _staticEngine,
    );
  }

  /// Calls a SHQL™ expression from a user-interaction callback (button press, tap, etc.).
  /// Catches any exception and shows it in a SnackBar rather than crashing the app.
  ///
  /// Handles the `CLOSE_DIALOG(value)` framework directive: SHQL™ evaluates the
  /// expression normally, CLOSE_DIALOG (a registered Dart function) returns a
  /// sentinel map, and this method intercepts it to call
  /// `Navigator.of(context).pop(value)`.  This is a native Dart callback that
  /// SHQL™ invokes for closing dialogs — the same pattern as file I/O or
  /// network calls.
  static void callShql(
    BuildContext context,
    ShqlBindings shql,
    String code, {
    bool targeted = false,
    Map<String, dynamic>? boundValues,
  }) {
    shql
        .call(code, targeted: targeted, boundValues: boundValues)
        .then((result) {
      if (result is Map &&
          result['__close_dialog__'] == true &&
          context.mounted) {
        var value = result['value'];
        // Convert SHQL™ Objects to Dart Maps so callers can use map syntax
        if (shql.isShqlObject(value)) {
          value = shql.objectToMap(value);
        }
        Navigator.of(context).pop(value);
      }
    }).catchError((Object e) {
      debugPrint('SHQL™ error: $e');
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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

/// A 3-tier widget registry for apps: custom factories → basic widgets → YAML templates.
///
/// Apps create an instance with their domain-specific widget factories.
/// The lookup order is: custom → basic (framework) → YAML templates.
class AppWidgetRegistry extends WidgetRegistry {
  final WidgetRegistry _basicRegistry;
  final Map<String, WidgetFactory> _customFactories;

  AppWidgetRegistry(this._basicRegistry, this._customFactories)
    : super({});

  /// Exposes custom factories for static registry registration.
  Map<String, WidgetFactory> get customFactories => _customFactories;

  @override
  WidgetFactory? get(String type) {
    if (_customFactories.containsKey(type)) {
      return _customFactories[type];
    }
    return _basicRegistry.get(type) ?? super.get(type);
  }

  @override
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
    if (_customFactories.containsKey(type)) {
      final key = ValueKey<String>(path);
      return _customFactories[type]!(
        context, props, buildChild, child, children, path, shql, key, engine,
      );
    }
    if (_basicRegistry.get(type) != null) {
      return _basicRegistry.build(
        type: type,
        context: context,
        props: props,
        buildChild: buildChild,
        child: child,
        children: children,
        path: path,
        shql: shql,
        engine: engine,
      );
    }
    return super.build(
      type: type,
      context: context,
      props: props,
      buildChild: buildChild,
      child: child,
      children: children,
      path: path,
      shql: shql,
      engine: engine,
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
  final bgColor = props['backgroundColor'];
  return Scaffold(
    key: key,
    backgroundColor: bgColor != null ? Resolvers.color(bgColor) : null,
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

  // Gradient: {type: 'linear', colors: ['0xFF...', '0xFF...']}
  Gradient? gradient;
  final gradientMap = decorationMap?['gradient'] as Map?;
  if (gradientMap != null) {
    final rawColors = gradientMap['colors'] as List?;
    if (rawColors != null) {
      final colors = rawColors
          .map((c) => Resolvers.color(c) ?? Colors.transparent)
          .toList();
      gradient = LinearGradient(colors: colors);
    }
  }

  // BoxShadow: [{blurRadius: 4, color: '0x42000000'}]
  List<BoxShadow>? boxShadow;
  final rawShadows = decorationMap?['boxShadow'] as List?;
  if (rawShadows != null) {
    boxShadow = rawShadows
        .whereType<Map>()
        .map((s) => BoxShadow(
              blurRadius: (s['blurRadius'] as num?)?.toDouble() ?? 0,
              color: Resolvers.color(s['color']) ?? Colors.black26,
              offset: Offset(
                (s['offsetX'] as num?)?.toDouble() ?? 0,
                (s['offsetY'] as num?)?.toDouble() ?? 0,
              ),
            ))
        .toList();
  }

  // Shape: 'circle' for BoxShape.circle
  final shapeStr = decorationMap?['shape']?.toString();
  final shape = shapeStr == 'circle' ? BoxShape.circle : BoxShape.rectangle;

  return Container(
    key: key,
    width: (props['width'] as num?)?.toDouble(),
    height: (props['height'] as num?)?.toDouble(),
    padding: Resolvers.edgeInsets(props['padding']),
    margin: Resolvers.edgeInsets(props['margin']),
    alignment: Resolvers.alignment(props['alignment'] as String?),
    decoration: BoxDecoration(
      color: Resolvers.color(props['color'] ?? decorationMap?['color']),
      borderRadius: shape == BoxShape.circle ? null : Resolvers.borderRadius(decorationMap?['borderRadius']),
      border: border,
      gradient: gradient,
      boxShadow: boxShadow,
      shape: shape,
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
  final cb = _resolveOnPressed(props['onPressed'], context, shql);

  return ElevatedButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : b({'type': 'Text', 'props': {'data': 'Button'}}, '$path.child'),
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
        : b({'type': 'SizedBox', 'props': {}}, '$path.child'),
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

  // Shape: borderRadius and optional side (border color/width)
  ShapeBorder? shape;
  final borderRadius = (props['borderRadius'] as num?)?.toDouble();
  final borderColor = props['borderColor'];
  final borderWidth = (props['borderWidth'] as num?)?.toDouble();
  if (borderRadius != null || borderColor != null) {
    shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius ?? 0),
      side: borderColor != null
          ? BorderSide(
              color: Resolvers.color(borderColor) ?? Colors.transparent,
              width: borderWidth ?? 1.0,
            )
          : BorderSide.none,
    );
  }

  final clipStr = props['clipBehavior']?.toString();
  Clip? clip;
  if (clipStr == 'antiAlias') clip = Clip.antiAlias;
  if (clipStr == 'hardEdge') clip = Clip.hardEdge;

  Widget card = Card(
    key: key,
    color: Resolvers.color(props['color']),
    elevation: (props['elevation'] as num?)?.toDouble(),
    shape: shape,
    clipBehavior: clip ?? Clip.none,
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
    return b({'type': 'SizedBox', 'props': {}}, '$path.fallback');
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
    this.dartOnSubmitted,
    this.initialValue,
    this.decoration,
    this.externalController,
    this.obscureText = false,
    this.autofocus = false,
    this.textInputAction,
    this.keyboardType,
    this.buildChild,
    this.path = '',
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final String? onChanged;
  final String? onSubmitted;
  final ValueChanged<String>? dartOnSubmitted;
  final String? initialValue;
  final Map<String, dynamic>? decoration;
  final TextEditingController? externalController;
  final bool obscureText;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final ChildBuilder? buildChild;
  final String path;
  final YamlUiEngine engine;

  @override
  State<_StatefulTextField> createState() => _StatefulTextFieldState();
}

class _StatefulTextFieldState extends State<_StatefulTextField> {
  TextEditingController? _ownController;
  late final Debouncer _debouncer;

  TextEditingController get _controller =>
      widget.externalController ?? (_ownController ??= TextEditingController(text: widget.initialValue));

  @override
  void initState() {
    super.initState();
    if (widget.externalController == null) {
      _ownController = TextEditingController(text: widget.initialValue);
    }
    _debouncer = Debouncer(milliseconds: 500);
  }

  @override
  void didUpdateWidget(covariant _StatefulTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalController == null &&
        widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.text = widget.initialValue ?? '';
        }
      });
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final decoration = widget.decoration ?? {};
    final onSubmitted = widget.onSubmitted;
    final b = widget.buildChild;

    // Build prefixIcon via registry if specified as a string icon name
    Widget? prefixIcon;
    final prefixIconValue = decoration['prefixIcon'];
    if (prefixIconValue is String && b != null) {
      prefixIcon = b(
        {'type': 'Icon', 'props': {'icon': prefixIconValue}},
        '${widget.path}.prefixIcon',
      );
    } else if (prefixIconValue is Widget) {
      prefixIcon = prefixIconValue;
    }

    // Build suffixIcon via registry if specified
    Widget? suffixIcon;
    final suffixIconValue = decoration['suffixIcon'];
    if (suffixIconValue is String && b != null) {
      suffixIcon = b(
        {'type': 'Icon', 'props': {'icon': suffixIconValue}},
        '${widget.path}.suffixIcon',
      );
    } else if (suffixIconValue is Widget) {
      suffixIcon = suffixIconValue;
    }

    final inputDecoration = InputDecoration(
      hintText: decoration['hintText']?.toString(),
      labelText: decoration['labelText']?.toString(),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: decoration['border'] == 'outline' ? const OutlineInputBorder() : null,
    );

    // Determine textInputAction
    final tia = widget.textInputAction ??
        (onSubmitted != null ? TextInputAction.done : null);

    return TextField(
      controller: _controller,
      obscureText: widget.obscureText,
      autofocus: widget.autofocus,
      textInputAction: tia,
      keyboardType: widget.keyboardType,
      onChanged: (value) {
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
        // Flush any pending debounced onChanged so the SHQL™ variable
        // is up-to-date before the submit handler reads it.
        _debouncer.flush();
        if (widget.dartOnSubmitted != null) {
          widget.dartOnSubmitted!(value);
        } else if (isShqlRef(onSubmitted)) {
          final (:code, :targeted) = parseShql(onSubmitted as String);
          widget.shql
              .call(code, targeted: targeted, boundValues: {'value': value})
              .catchError((e) {
                debugPrint('Error in onSubmitted: $e');
              });
        }
      },
      decoration: inputDecoration,
    );
  }
}

TextInputType? _resolveKeyboardType(dynamic v) {
  if (v is TextInputType) return v;
  switch (v?.toString()) {
    case 'emailAddress': return TextInputType.emailAddress;
    case 'number': return TextInputType.number;
    case 'phone': return TextInputType.phone;
    case 'url': return TextInputType.url;
    case 'multiline': return TextInputType.multiline;
    case 'text': return TextInputType.text;
    default: return null;
  }
}

TextInputAction? _resolveTextInputAction(dynamic v) {
  if (v is TextInputAction) return v;
  switch (v?.toString()) {
    case 'done': return TextInputAction.done;
    case 'next': return TextInputAction.next;
    case 'search': return TextInputAction.search;
    case 'send': return TextInputAction.send;
    case 'go': return TextInputAction.go;
    default: return null;
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
    dartOnSubmitted: props['dartOnSubmitted'] as ValueChanged<String>?,
    initialValue: (props['value'] ?? props['initialValue'])?.toString(),
    decoration: (props['decoration'] as Map?)?.cast<String, dynamic>(),
    externalController: props['controller'] as TextEditingController?,
    obscureText: props['obscureText'] == true,
    autofocus: props['autofocus'] == true,
    textInputAction: _resolveTextInputAction(props['textInputAction']),
    keyboardType: _resolveKeyboardType(props['keyboardType']),
    buildChild: b,
    path: path,
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

  final padding = props['padding'];
  return SingleChildScrollView(
    key: key,
    padding: padding != null ? Resolvers.edgeInsets(padding) : null,
    child: b(child, '$path.child'),
  );
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
      return widget.buildChild({
        'type': 'SizedBox',
        'props': {
          'width': 20,
          'height': 20,
          'child': {
            'type': 'CircularProgressIndicator',
            'props': {'strokeWidth': 2},
          },
        },
      }, '${widget.path}.loading');
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

  final fitStr = props['fit']?.toString();
  final fit = fitStr == 'expand' ? StackFit.expand
      : fitStr == 'passthrough' ? StackFit.passthrough
      : StackFit.loose;

  return Stack(
    key: key,
    fit: fit,
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
        : b({'type': 'SizedBox', 'props': {}}, '$path.child'),
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
  final valueColor = props['valueColor'];
  return CircularProgressIndicator(
    key: key,
    value: (props['value'] as num?)?.toDouble(),
    backgroundColor: Resolvers.color(props['backgroundColor']),
    color: Resolvers.color(props['color']),
    strokeWidth: (props['strokeWidth'] as num?)?.toDouble() ?? 4.0,
    valueColor: valueColor != null
        ? AlwaysStoppedAnimation<Color>(Resolvers.color(valueColor)!)
        : null,
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
  final valueColor = props['valueColor'];
  final minHeight = (props['minHeight'] as num?)?.toDouble();
  final borderRadius = (props['borderRadius'] as num?)?.toDouble();
  return LinearProgressIndicator(
    key: key,
    value: (props['value'] as num?)?.toDouble(),
    backgroundColor: Resolvers.color(props['backgroundColor']),
    color: Resolvers.color(props['color']),
    valueColor: valueColor != null
        ? AlwaysStoppedAnimation<Color>(Resolvers.color(valueColor)!)
        : null,
    minHeight: minHeight,
    borderRadius: borderRadius != null
        ? BorderRadius.circular(borderRadius)
        : null,
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
    label: b({'type': 'Text', 'props': {'data': label}}, '$path.label'),
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
  final cb = _resolveOnPressed(props['onPressed'], context, shql);

  return TextButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : b({'type': 'Text', 'props': {'data': 'Button'}}, '$path.child'),
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
  final cb = _resolveOnPressed(props['onPressed'], context, shql);

  return OutlinedButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : b({'type': 'Text', 'props': {'data': 'Button'}}, '$path.child'),
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
    label: b({'type': 'Text', 'props': {'data': label}}, '$path.label'),
    selected: selected,
    onSelected: cb,
  );
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

// ---------------------------------------------------------------------------
// Icon
// ---------------------------------------------------------------------------

Widget _buildIcon(
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
  final iconName = props['icon'] as String? ?? 'help_outline';
  final size = (props['size'] as num?)?.toDouble();
  final color = Resolvers.color(props['color']);
  return Icon(Resolvers.iconData(iconName), key: key, size: size, color: color);
}

// ---------------------------------------------------------------------------
// IconButton
// ---------------------------------------------------------------------------

Widget _buildIconButton(
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
  final iconName = props['icon'] as String?;
  final onPressed = props['onPressed'];

  VoidCallback? cb;
  if (onPressed is VoidCallback) {
    cb = onPressed;
  } else if (onPressed is String && isShqlRef('shql: $onPressed')) {
    cb = () => WidgetRegistry.callShql(context, shql, onPressed);
  }

  return IconButton(
    key: key,
    icon: b(
      {'type': 'Icon', 'props': {'icon': iconName ?? 'help_outline'}},
      '$path.icon',
    ),
    onPressed: cb,
  );
}

// ---------------------------------------------------------------------------
// SafeArea
// ---------------------------------------------------------------------------

Widget _buildSafeArea(
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
  return SafeArea(
    key: key,
    child: childNode != null
        ? b(childNode, '$path.child')
        : b({'type': 'SizedBox', 'props': {}}, '$path.child'),
  );
}

// ---------------------------------------------------------------------------
// ListTile
// ---------------------------------------------------------------------------

Widget _buildListTile(
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
  final titleNode = props['title'];
  final subtitleNode = props['subtitle'];
  final trailingNode = props['trailing'];
  final onTap = props['onTap'] as String?;

  VoidCallback? cb;
  if (onTap != null && isShqlRef(onTap)) {
    final (:code, :targeted) = parseShql(onTap);
    cb = () => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
  }

  return ListTile(
    key: key,
    dense: props['dense'] as bool? ?? false,
    leading: leadingNode != null ? b(leadingNode, '$path.leading') : null,
    title: titleNode != null ? b(titleNode, '$path.title') : null,
    subtitle: subtitleNode != null ? b(subtitleNode, '$path.subtitle') : null,
    trailing: trailingNode != null ? b(trailingNode, '$path.trailing') : null,
    onTap: cb,
  );
}

// ---------------------------------------------------------------------------
// BottomNavigationBar
// ---------------------------------------------------------------------------

Widget _buildBottomNavigationBar(
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
  final items = props['items'] as List? ?? [];
  final currentIndex = props['currentIndex'] as int? ?? 0;
  final onTap = props['onTap'] as String?;

  return BottomNavigationBar(
    key: key,
    currentIndex: currentIndex,
    onTap: onTap != null
        ? (index) {
            WidgetRegistry.callShql(
              context, shql, onTap.replaceAll('value', '$index'),
            );
          }
        : null,
    items: items.asMap().entries.map<BottomNavigationBarItem>((entry) {
      final map = entry.value as Map;
      return BottomNavigationBarItem(
        icon: b(
          {'type': 'Icon', 'props': {'icon': map['icon'] as String? ?? 'help'}},
          '$path.items[${entry.key}].icon',
        ),
        label: map['label'] as String? ?? '',
      );
    }).toList(),
  );
}

// ---------------------------------------------------------------------------
// AnimatedNumber
// ---------------------------------------------------------------------------

Widget _buildAnimatedNumber(
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
  final rawValue = props['value'];
  final value = rawValue is num
      ? rawValue
      : num.tryParse(rawValue?.toString() ?? '') ?? 0;
  final duration = (props['duration'] as int?) ?? 800;
  final fontSize = (props['fontSize'] as num?)?.toDouble();
  final fontWeight = props['fontWeight']?.toString();
  final color = props['color'];
  return AnimatedNumber(
    key: key,
    value: value,
    duration: Duration(milliseconds: duration),
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight == 'bold' ? FontWeight.bold : null,
      color: color != null ? Resolvers.color(color) : null,
    ),
  );
}

/// Resolves an onPressed prop that may be a SHQL™ expression string,
/// a Dart VoidCallback, or null.
VoidCallback? _resolveOnPressed(
  dynamic onPressed,
  BuildContext context,
  ShqlBindings shql,
) {
  if (onPressed is VoidCallback) return onPressed;
  if (isShqlRef(onPressed)) {
    final (:code, :targeted) = parseShql(onPressed as String);
    return () => WidgetRegistry.callShql(context, shql, code, targeted: targeted);
  }
  return null;
}

Widget _buildFilledButton(
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
  final cb = _resolveOnPressed(props['onPressed'], context, shql);

  return FilledButton(
    key: key,
    onPressed: cb,
    child: childNode != null
        ? b(childNode, '$path.child')
        : b({'type': 'Text', 'props': {'data': 'Button'}}, '$path.child'),
  );
}

Widget _buildAlertDialog(
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
  final titleNode = props['title'];
  final contentNode = props['content'] ?? child;
  final actionsRaw = props['actions'] ?? children;

  final List<Widget> actions = [];
  if (actionsRaw is List) {
    for (var i = 0; i < actionsRaw.length; i++) {
      actions.add(b(actionsRaw[i], '$path.actions[$i]'));
    }
  }

  final actionsAlignment = props['actionsAlignment']?.toString();
  MainAxisAlignment? alignment;
  if (actionsAlignment == 'spaceEvenly') {
    alignment = MainAxisAlignment.spaceEvenly;
  } else if (actionsAlignment == 'center') {
    alignment = MainAxisAlignment.center;
  } else if (actionsAlignment == 'end') {
    alignment = MainAxisAlignment.end;
  }

  return AlertDialog(
    key: key,
    title: titleNode != null ? b(titleNode, '$path.title') : null,
    content: contentNode != null ? b(contentNode, '$path.content') : null,
    actions: actions.isEmpty ? null : actions,
    actionsAlignment: alignment,
  );
}

Widget _buildCheckboxListTile(
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
  final titleNode = props['title'];
  final contentPadding = props['contentPadding'];

  return _StatefulCheckboxListTile(
    key: key,
    shql: shql,
    onChanged: props['onChanged'] as String?,
    value: props['value'],
    title: titleNode != null ? b(titleNode, '$path.title') : null,
    contentPadding: contentPadding != null ? Resolvers.edgeInsets(contentPadding) : null,
    engine: engine,
  );
}

class _StatefulCheckboxListTile extends StatefulWidget {
  const _StatefulCheckboxListTile({
    required this.shql,
    this.onChanged,
    this.value,
    this.title,
    this.contentPadding,
    required this.engine,
    super.key,
  });

  final ShqlBindings shql;
  final String? onChanged;
  final dynamic value;
  final Widget? title;
  final EdgeInsetsGeometry? contentPadding;
  final YamlUiEngine engine;

  @override
  State<_StatefulCheckboxListTile> createState() =>
      _StatefulCheckboxListTileState();
}

class _StatefulCheckboxListTileState
    extends State<_StatefulCheckboxListTile> {
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
      debugPrint('Error resolving CheckboxListTile value: $e');
    }
  }

  void _onDataChanged() {
    if (mounted) {
      _resolveValue();
    }
  }

  @override
  void didUpdateWidget(covariant _StatefulCheckboxListTile oldWidget) {
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
    return CheckboxListTile(
      value: _currentValue,
      title: widget.title,
      contentPadding: widget.contentPadding,
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
                debugPrint('Error in CheckboxListTile onChanged: $e');
              });
        }
      },
    );
  }
}

Widget _buildConstrainedBox(
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
  final maxWidth = (props['maxWidth'] as num?)?.toDouble() ?? double.infinity;
  final maxHeight = (props['maxHeight'] as num?)?.toDouble() ?? double.infinity;
  final minWidth = (props['minWidth'] as num?)?.toDouble() ?? 0.0;
  final minHeight = (props['minHeight'] as num?)?.toDouble() ?? 0.0;

  return ConstrainedBox(
    key: key,
    constraints: BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minWidth: minWidth,
      minHeight: minHeight,
    ),
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}

Widget _buildInkWell(
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
  final cb = _resolveOnPressed(props['onTap'], context, shql);
  final borderRadiusVal = (props['borderRadius'] as num?)?.toDouble();

  return InkWell(
    key: key,
    onTap: cb,
    borderRadius: borderRadiusVal != null
        ? BorderRadius.circular(borderRadiusVal)
        : null,
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}

Widget _buildMaterial(
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
  final color = props['color'];
  final borderRadiusVal = (props['borderRadius'] as num?)?.toDouble();

  return Material(
    key: key,
    color: color != null ? Resolvers.color(color) : null,
    borderRadius: borderRadiusVal != null
        ? BorderRadius.circular(borderRadiusVal)
        : null,
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}

Widget _buildDismissible(
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
  final backgroundNode = props['background'];
  final onDismissed = props['onDismissed'];

  // Use confirmDismiss to trigger the delete, then return false.
  // The SHQL™ delete removes the item from the data list, which triggers a
  // rebuild that removes the Dismissible from the tree naturally.
  // Returning true would crash: the async delete rebuilds the tree mid-await,
  // so the Dismissible is disposed before confirmDismiss returns.
  ConfirmDismissCallback? confirm;
  if (onDismissed is DismissDirectionCallback) {
    confirm = (direction) async { onDismissed(direction); return false; };
  } else if (onDismissed is VoidCallback) {
    confirm = (_) async { onDismissed(); return false; };
  } else if (isShqlRef(onDismissed)) {
    final (:code, :targeted) = parseShql(onDismissed as String);
    confirm = (_) async {
      shql.call(code, targeted: targeted);
      return false;
    };
  }

  final directionStr = props['direction']?.toString();
  DismissDirection direction = DismissDirection.endToStart;
  if (directionStr == 'startToEnd') direction = DismissDirection.startToEnd;
  if (directionStr == 'horizontal') direction = DismissDirection.horizontal;

  return Dismissible(
    key: key,
    direction: direction,
    background: backgroundNode != null ? b(backgroundNode, '$path.background') : null,
    confirmDismiss: confirm,
    child: childNode != null
        ? b(childNode, '$path.child')
        : const SizedBox.shrink(),
  );
}

Widget _buildSemantics(
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
  final label = props['label']?.toString();
  final button = props['button'] == true;

  return Semantics(
    key: key,
    label: label,
    button: button,
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}

Widget _buildTooltip(
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
  final message = props['message']?.toString() ?? '';

  return Tooltip(
    key: key,
    message: message,
    child: childNode != null ? b(childNode, '$path.child') : null,
  );
}
