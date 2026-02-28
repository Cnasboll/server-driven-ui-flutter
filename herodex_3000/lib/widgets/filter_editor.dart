import 'package:flutter/material.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

/// HeroDex-specific filter editor widget.
///
/// Reads/writes SHQL™ variables (`_filters`, `_filter_counts`, etc.) and calls
/// SHQL™ functions (`APPLY_FILTER`, `SAVE_FILTER`, etc.) that are defined in
/// filters.shql. This is domain-specific to HeroDex and does NOT belong in the
/// generic server_driven_ui framework.
Widget buildFilterEditor(
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
  return _FilterEditor(
    key: key,
    shql: shql,
    mode: mode,
    onSelect: onSelect,
    buildChild: b,
    path: path,
  );
}

class _FilterEditor extends StatefulWidget {
  const _FilterEditor({
    required this.shql,
    required this.mode,
    required this.buildChild,
    required this.path,
    this.onSelect,
    super.key,
  });

  final ShqlBindings shql;
  final String mode; // 'manage' or 'apply'
  final String? onSelect; // SHQL™ expression to run after selecting a filter
  final ChildBuilder buildChild;
  final String path;

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

  /// Shorthand for widget.buildChild — builds a leaf widget via the registry.
  Widget _b(Map<String, dynamic> node, String subpath) =>
      widget.buildChild(node, '${widget.path}.$subpath');

  late final TextEditingController _queryController;
  late final TextEditingController _nameController;
  late final Debouncer _debouncer;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _nameFocusNode = FocusNode();

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
    _nameFocusNode.dispose();
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
    // Auto-select the newly added filter, scroll to it, and focus the name field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_filters.isNotEmpty) {
        _selectChip(_filters.length - 1);
        // After selecting (which triggers setState), scroll on next frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          _nameFocusNode.requestFocus();
        });
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
                  leading: _b({'type': 'Icon', 'props': {'icon': 'select_all', 'size': 20}}, 'allIcon'),
                  title: _b({'type': 'Text', 'props': {'data': 'All'}}, 'allLabel'),
                  trailing: _b({'type': 'Text', 'props': {
                    'data': '$_totalHeroes',
                    'style': {'fontWeight': 'bold'},
                  }}, 'allCount'),
                  selected: _activeFilterIndex == -1 && _editingIndex == -1,
                  onTap: () => _selectAll(),
                ),
              for (int i = 0; i < _filters.length; i++)
                ListTile(
                  dense: true,
                  leading: _b({'type': 'Icon', 'props': {
                    'icon': _isApplyMode && _activeFilterIndex == i
                        ? 'check_circle'
                        : 'filter_list',
                    'size': 20,
                  }}, 'filterIcon[$i]'),
                  title: _b({'type': 'Text', 'props': {
                    'data': _filters[i]['name']?.toString() ?? 'Unnamed',
                  }}, 'filterName[$i]'),
                  trailing: _b({'type': 'Text', 'props': {
                    'data': i < _filterCounts.length ? '${_filterCounts[i]}' : '',
                    'style': {'fontWeight': 'bold'},
                  }}, 'filterCount[$i]'),
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
                focusNode: _nameFocusNode,
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
          _b({'type': 'SizedBox', 'props': {'height': 4}}, 'nameGap'),
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
                icon: _b({'type': 'Icon', 'props': {'icon': 'add', 'size': 18}}, 'addIcon'),
                label: _b({'type': 'Text', 'props': {'data': 'Add Filter'}}, 'addLabel'),
                onPressed: _addFilter,
              ),
              if (_editingIndex >= 0)
                OutlinedButton.icon(
                  icon: _b({'type': 'Icon', 'props': {'icon': 'delete', 'size': 18}}, 'deleteIcon'),
                  label: _b({'type': 'Text', 'props': {'data': 'Delete'}}, 'deleteLabel'),
                  onPressed: _deleteFilter,
                ),
              OutlinedButton.icon(
                icon: _b({'type': 'Icon', 'props': {'icon': 'restore', 'size': 18}}, 'resetIcon'),
                label: _b({'type': 'Text', 'props': {'data': 'Reset Defaults'}}, 'resetLabel'),
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
                _b({'type': 'LinearProgressIndicator', 'props': {}}, 'progress'),
                _b({'type': 'SizedBox', 'props': {'height': 4}}, 'progressGap'),
                _b({'type': 'Text', 'props': {
                  'data': _compiling ? 'Compiling filters...' : 'Applying filter...',
                }}, 'progressLabel'),
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
          hintText: 'SHQL™ expression or plaintext search',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: _b({'type': 'Icon', 'props': {
              'icon': _isApplyMode ? 'play_arrow' : 'save',
            }}, 'queryIcon'),
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
