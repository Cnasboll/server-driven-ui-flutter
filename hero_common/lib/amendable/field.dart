import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/callbacks.dart';
import 'package:hero_common/utils/enum_parsing.dart';
import 'package:hero_common/utils/json_parsing.dart';
import 'package:hero_common/value_types/percentage.dart';

typedef LookupField<T, V> = V? Function(T);
typedef FormatField<T> = String Function(T);
typedef SQLGetter<T> = Object? Function(T);
typedef SHQLGetter<T> = Object? Function(T);
typedef ValidateInput = (bool, String?) Function(String);

class Field<T, V> implements FieldBase<T> {
  factory Field(
    LookupField<T, V> getter,
    String name,
    String description, {
    bool primary = false,
    bool? nullable,
    FormatField<T>? format,
    FormatField<T>? formatEx,
    bool comparable = true,
    String? prompt,
    bool? assignedBySystem,
    bool? mutable,
    String? jsonName,
    String? sqliteName,
    String? shqlName,
    String? displayName,
    List<FieldBase>? children,
    SQLGetter<T>? sqliteGetter,
    SHQLGetter<T>? shqlGetter,
    bool childrenForDbOnly = false,
    List<String> extraNullLiterals = const [],
    ValidateInput? validateInput,
    bool showInSummary = false,
    bool showInDetail = true,
  }) {
    assignedBySystem = assignedBySystem ?? primary;
    nullable = nullable ?? !assignedBySystem;
    mutable = mutable ?? !primary;
    // Derive jsonName and sqliteName from name if not provided, not from each other
    // to avoid accidental collisions (i.e. in our db we use British spelling for some fields as we control it)
    jsonName = jsonName ?? (name.replaceAll(' ', '-').toLowerCase());
    sqliteName =
        sqliteName ??
        (name.replaceAll(' ', '-').replaceAll('-', '_').toLowerCase());
    shqlName = shqlName ?? sqliteName;
    displayName = displayName ?? name;
    format = format ?? ((t) => getter(t).toString());
    formatEx = formatEx ?? ((t) => '');
    children = children ?? <FieldBase>[];
    sqliteGetter = sqliteGetter ?? ((t) => getter(t));
    shqlGetter = shqlGetter ?? sqliteGetter;
    validateInput = validateInput ?? ((s) => (true, null));

    return Field._internal(
      getter,
      name,
      jsonName,
      sqliteName,
      shqlName,
      displayName,
      description,
      format,
      formatEx,
      sqliteGetter,
      shqlGetter,
      primary,
      nullable,
      mutable,
      assignedBySystem,
      comparable,
      prompt,
      children,
      childrenForDbOnly,
      extraNullLiterals,
      validateInput,
      showInSummary,
      showInDetail,
    );
  }

  Field._internal(
    this._getter,
    this._name,
    this.jsonName,
    this.sqliteName,
    this.shqlName,
    this.displayName,
    this.description,
    this.format,
    this.formatEx,
    this.sqliteGetter,
    this.shqlGetter,
    this.primary,
    this.nullable,
    this._mutable,
    this.assignedBySystem,
    this.comparable,
    this.prompt,
    this._children,
    this.childrenForDbOnly,
    this.extraNullLiterals,
    this.validateInput,
    this.showInSummary,
    this.showInDetail,
  );

  // DRY for type: infer T from the getter's return type
  factory Field.infer(
    LookupField<T, V> getter,
    String name,
    String description, {
    bool primary = false,
    bool? nullable,
    FormatField<T>? format,
    FormatField<T>? formatEx,
    bool comparable = true,
    String? prompt,
    bool? assignedBySystem,
    bool? mutable,
    String? jsonName,
    String? sqliteName,
    String? shqlName,
    String? displayName,
    List<FieldBase>? children,
    SQLGetter<T>? sqliteGetter,
    SHQLGetter<T>? shqlGetter,
    bool childrenForDbOnly = false,
    List<String> extraNullLiterals = const [],
    ValidateInput? validateInput,
    bool showInSummary = false,
    bool showInDetail = true,
  }) {
    return Field<T, V>(
      getter,
      name,
      description,
      primary: primary,
      nullable: nullable,
      format: format,
      formatEx: formatEx,
      comparable: comparable,
      prompt: prompt,
      assignedBySystem: assignedBySystem,
      mutable: mutable,
      jsonName: jsonName,
      sqliteName: sqliteName,
      shqlName: shqlName,
      displayName: displayName,
      children: children,
      sqliteGetter: sqliteGetter,
      shqlGetter: shqlGetter,
      childrenForDbOnly: childrenForDbOnly,
      extraNullLiterals: extraNullLiterals,
      validateInput: validateInput,
      showInSummary: showInSummary,
      showInDetail: showInDetail,
    );
  }

  static String growCrumbTrail(String? crumbtrail, String name) {
    var cr = crumbtrail != null ? "$crumbtrail: " : "";
    return '$cr$name';
  }

  @override
  Future<bool> promptForJson(
    Map<String, dynamic> json, {
    String? crumbtrail,
  }) async {
    if (Callbacks.onPromptFor == null || Callbacks.onPrintln == null || Callbacks.onPromptForYesNo == null) {
      throw UnimplementedError('promptForJson requires terminal callbacks. Call Callbacks.configure() first.');
    }
    if (assignedBySystem) {
      return true;
    }
    var fullPath = growCrumbTrail(crumbtrail, name);
    if (_children.isEmpty || childrenForDbOnly) {
      String abortPrompt = crumbtrail != null
          ? "finish populating $crumbtrail"
          : "abort";
      var promptSuffix = prompt != null ? '$prompt' : '';
      for (;;) {
        var input = await Callbacks.onPromptFor!(
          "Enter $fullPath ($description$promptSuffix), or enter to $abortPrompt:",
        );
        if (input.isEmpty) {
          return false;
        }
        var (isValid, error) = validateInput(input);
        if (isValid) {
          json[jsonName] = input;
          return true;
        }
        Callbacks.onPrintln!(
          "Invalid value for $fullPath ($description$promptSuffix), please try again: ${error ?? ''}",
        );
      }
    }

    if (await Callbacks.onPromptForYesNo!('Populate $fullPath ($description)?')) {
      var childJson = json[jsonName] = <String, dynamic>{};
      for (var child in _children) {
        if (!await child.promptForJson(childJson, crumbtrail: fullPath)) {
          return true;
        }
      }
    }
    return true;
  }

  @override
  Future<void> promptForAmendmentJson(
    T t,
    Map<String, dynamic> amendment, {
    String? crumbtrail,
  }) async {
    if (Callbacks.onPromptFor == null || Callbacks.onPrintln == null || Callbacks.onPromptForYes == null) {
      throw UnimplementedError('promptForAmendmentJson requires terminal callbacks. Call Callbacks.configure() first.');
    }
    if (!mutable || assignedBySystem) {
      return;
    }
    var fullPath = growCrumbTrail(crumbtrail, name);
    if (_children.isEmpty || childrenForDbOnly) {
      var promptSuffix = prompt != null ? '$prompt' : '';
      var current = format(t);
      for (;;) {
        var input = await Callbacks.onPromptFor!(
          "Enter $fullPath ($description$promptSuffix), or enter to keep current value ($current):",
        );
        if (input.isEmpty) {
          return;
        }
        var (isValid, error) = validateInput(input);
        if (isValid) {
          amendment[jsonName] = input;
          break;
        }
        Callbacks.onPrintln!(
          "Invalid value for $fullPath ($description$promptSuffix), please try again: ${error ?? ''}",
        );
      }
      return;
    }

    if (await Callbacks.onPromptForYes!('Amend $fullPath ($description)?')) {
      var childAmendment = amendment[jsonName] = <String, dynamic>{};
      for (var child in _children) {
        await child.promptForAmendmentJson(
          getter(t),
          childAmendment,
          crumbtrail: fullPath,
        );
      }
    }
  }

  @override
  bool validateAmendment(T lhs, T rhs) {
    if (lhs == rhs || mutable) {
      return true;
    }
    for (var child in _children) {
      if (!child.validateAmendment(lhs, rhs)) {
        return false;
      }
    }
    return mutable;
  }

  @override
  bool matches(T t, String query) {
    var value = getter(t);
    if (value == null) {
      return false;
    }

    if (_children.isEmpty || childrenForDbOnly) {
      return format(t).toLowerCase().contains(query);
    }

    for (var child in _children) {
      if (child.matches(value, query)) {
        return true;
      }
    }
    return false;
  }

  @override
  void formatField(T t, StringBuffer sb, {String? crumbtrail}) {
    var fullPath = growCrumbTrail(crumbtrail, name);
    if (_children.isEmpty || childrenForDbOnly) {
      sb.writeln("$fullPath: ${format(t)}${formatEx(t)}");
      return;
    }

    var childObject = getter(t);
    if (childObject == null) {
      sb.writeln("$fullPath: null");
      return;
    }

    for (var child in _children) {
      child.formatField(childObject, sb, crumbtrail: fullPath);
    }
  }

  @override
  bool diff(T lhs, T rhs, StringBuffer sb, {String? crumbtrail}) {
    var lhsValue = getter(lhs);
    var rhsValue = getter(rhs);

    if (!mutable || assignedBySystem || deepEq.equals(lhsValue, rhsValue)) {
      return false;
    }

    var fullPath = growCrumbTrail(crumbtrail, name);
    if (_children.isEmpty || childrenForDbOnly) {
      sb.writeln("$fullPath: ${format(lhs)} -> ${format(rhs)}");
      return true;
    }

    bool hasChildDifferences = false;
    for (var child in _children) {
      hasChildDifferences |= child.diff(
        lhsValue,
        rhsValue,
        sb,
        crumbtrail: fullPath,
      );
    }
    return hasChildDifferences;
  }

  @override
  int compareField(T lhs, T rhs) {
    if (!comparable) {
      // Not part of comparison
      return 0;
    }

    var lhsValue = getter(lhs);
    var rhsValue = getter(rhs);

    if (lhsValue == null && rhsValue == null) {
      return 0;
    }

    if (lhsValue == null) {
      return -1; // null is considered smaller
    }

    if (rhsValue == null) {
      return 1;
    }

    // If both implement Comparable, use that (most common case).
    if (lhsValue is Comparable && rhsValue is Comparable) {
      try {
        final cmp = lhsValue.compareTo(rhsValue);
        if (cmp != 0) {
          return cmp;
        }
        return 0;
      } catch (_) {
        // Fall through to other strategies if compareTo throws or isn't compatible.
      }
    }

    // Booleans: true > false
    if (lhsValue is bool && rhsValue is bool) {
      if (lhsValue != rhsValue) {
        return lhsValue ? 1 : -1;
      }
      return 0;
    }

    // Enums: compare by index
    if (lhsValue is Enum && rhsValue is Enum) {
      final cmp = lhsValue.index.compareTo(rhsValue.index);
      if (cmp != 0) {
        return cmp;
      }
      return 0;
    }

    // Deep-equal complex structures -> treat equal
    if (deepEq.equals(lhsValue, rhsValue)) {
      return 0;
    }

    // Last resort: compare string representations to provide a deterministic
    // ordering even for unknown / mixed types.
    final lstr = lhsValue.toString();
    final rstr = rhsValue.toString();
    final cmp = lstr.compareTo(rstr);
    if (cmp != 0) {
      return cmp;
    }
    return 0;
  }

  @override
  int? getIntForAmendment(T t, Map<String, dynamic>? amendment) {
    return getNullableInt(amendment) ?? getter(t) as int?;
  }

  @override
  int getIntFromJson(Map<String, dynamic>? json, int defaultValue) {
    return getNullableInt(json) ?? defaultValue;
  }

  @override
  int? getNullableInt(Map<String, dynamic>? json) {
    var value = json?[jsonName];

    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }
    var s = specialNullCoalesce(value, extraNullLiterals: extraNullLiterals);
    if (s == null) {
      return null;
    }
    return int.tryParse(s);
  }

  @override
  int getIntFromRow(Row row, int defaultValue) {
    return getNullableIntFromRow(row) ?? defaultValue;
  }

  @override
  int? getNullableIntFromRow(Row row) {
    return row[sqliteName] as int?;
  }

  @override
  Percentage? getPercentageForAmendment(
    T t,
    Map<String, dynamic>? amendment, {
    ParsingContext? parsingContext,
  }) {
    var value = getIntForAmendment(t, amendment);
    if (value == null) {
      return null;
    }
    return Percentage(value, parsingContext: parsingContext);
  }

  @override
  Percentage getPercentageFromJson(
    Map<String, dynamic>? json,
    int defaultValue, {
    ParsingContext? parsingContext,
  }) {
    return Percentage(
      getIntFromJson(json, defaultValue),
      parsingContext: parsingContext,
    );
  }

  @override
  Percentage? getNullablePercentage(
    Map<String, dynamic>? json, {
    ParsingContext? parsingContext,
  }) {
    var value = getNullableInt(json);
    if (value == null) {
      return null;
    }
    return Percentage(value, parsingContext: parsingContext);
  }

  @override
  Percentage getPercentageFromRow(Row row, int defaultValue) {
    return Percentage(getIntFromRow(row, defaultValue));
  }

  @override
  Percentage? getNullablePercentageFromRow(Row row) {
    var value = getNullableIntFromRow(row);
    if (value == null) {
      return null;
    }
    return Percentage(value);
  }

  @override
  double getFloatFromRow(Row row, double defaultValue) {
    return getNullableFloatFromRow(row) ?? defaultValue;
  }

  @override
  double? getNullableFloatFromRow(Row row) {
    return row[sqliteName] as double?;
  }

  @override
  bool getBoolFromRow(Row row, bool defaultValue) {
    return getNullableBoolFromRow(row) ?? defaultValue;
  }

  @override
  bool? getNullableBoolFromRow(Row row) {
    var v = getNullableIntFromRow(row);
    if (v == null) {
      return null;
    }
    return v != 0;
  }

  @override
  String getStringForAmendment(T t, Map<String, dynamic>? amendment) {
    return getString(amendment, getter(t) as String);
  }

  @override
  String? getNullableStringForAmendment(T t, Map<String, dynamic>? amendment) {
    return getNullableString(amendment) ?? getter(t) as String?;
  }

  @override
  String? getNullableString(Map<String, dynamic>? json) {
    return specialNullCoalesce(
      json?[jsonName],
      extraNullLiterals: extraNullLiterals,
    );
  }

  @override
  String getString(Map<String, dynamic>? json, String defaultValue) {
    return getNullableString(json) ?? defaultValue;
  }

  @override
  Map<String, dynamic>? getJson(Map<String, dynamic>? json) {
    return json?[jsonName] as Map<String, dynamic>?;
  }

  @override
  String? getNullableStringFromRow(Row row) {
    return row[sqliteName] as String?;
  }

  @override
  String getStringFromRow(Row row, String defaultValue) {
    return getNullableStringFromRow(row) ?? defaultValue;
  }

  @override
  List<String> getStringListFromJsonForAmendment(
    T t,
    Map<String, dynamic>? amendment,
  ) {
    return getStringList(amendment, getter(t) as List<String>);
  }

  @override
  List<String>? getNullableStringListFromJsonForAmendment(
    T t,
    Map<String, dynamic>? amendment,
  ) {
    var l = getNullableStringList(amendment);

    if (l != null) {
      return l;
    }

    var current = getter(t);

    if (current == null) {
      return null;
    }

    if (current is List<String>) {
      return current;
    }

    return [current.toString()];
  }

  @override
  List<String> getStringList(
    Map<String, dynamic>? json,
    List<String> defaultValue,
  ) {
    return getNullableStringList(json) ?? defaultValue;
  }

  @override
  List<String>? getNullableStringList(Map<String, dynamic>? json) {
    return getNullableStringListFromMap(json, jsonName);
  }

  @override
  List<String> getStringListFromRow(Row row, List<String> defaultValue) {
    return getNullableStringListFromRow(row) ?? defaultValue;
  }

  @override
  List<String>? getNullableStringListFromRow(Row row) {
    var json = getNullableStringFromRow(row);
    if (json == null) {
      return null;
    }
    return jsonDecode(json)?.cast<String>();
  }

  @override
  DateTime getDateTimeFromRow(Row row, DateTime defaultValue) {
    return getNullableDateTimeFromRow(row) ?? defaultValue;
  }

  @override
  DateTime? getNullableDateTimeFromRow(Row row) {
    var s = getNullableStringFromRow(row);
    if (s == null) {
      return null;
    }
    return DateTime.tryParse(s);
  }

  @override
  E getEnumForAmendment<E extends Enum>(
    T t,
    Iterable<E> enumValues,
    Map<String, dynamic>? amendment,
  ) {
    return getEnum(enumValues, amendment, getter(t) as E);
  }

  @override
  E getEnum<E extends Enum>(
    Iterable<E> enumValues,
    Map<String, dynamic>? amendment,
    E defaultValue,
  ) {
    return enumValues.findMatch(getString(amendment, defaultValue.name)) ??
        defaultValue;
  }

  @override
  E getEnumFromRow<E extends Enum>(
    Iterable<E> enumValues,
    Row row,
    E defaultValue,
  ) {
    return enumValues.findMatch(
          getNullableStringFromRow(row) ?? defaultValue.name,
        ) ??
        defaultValue;
  }

  @override
  String sqliteQualifier() {
    if (primary) {
      return 'PRIMARY KEY';
    }

    var qualifier = nullable ? '' : 'NOT ';
    return '${qualifier}NULL';
  }

  static final Map<Type, String> _sqliteColumnTypes = {
    int: 'INTEGER',
    String: 'TEXT',
    bool: 'BOOLEAN',
    double: 'REAL',
    Enum: 'TEXT',
  };

  @override
  String generateSqliteColumnType() {
    String columnType = _sqliteColumnTypes[V] ?? 'TEXT';
    return "$columnType ${sqliteQualifier()}";
  }

  @override
  List<Object?> sqliteProps(T t) {
    if (_children.isEmpty) {
      return [sqliteGetter(t)];
    }
    return _children.expand((c) => c.sqliteProps(getter(t))).toList();
  }

  @override
  String generateSQLiteInsertColumnPlaceholders() {
    if (_children.isEmpty) {
      return "?";
    }
    return _children
        .map((c) => c.generateSQLiteInsertColumnPlaceholders())
        .join(',');
  }

  @override
  String generateSqliteColumnNameList(String indent) {
    if (_children.isEmpty) {
      return sqliteName;
    }
    return _children
        .map((c) => c.generateSqliteColumnNameList(indent))
        .join(',\n$indent');
  }

  @override
  String generateSqliteColumnDeclarations(String indent) {
    if (_children.isEmpty) {
      return "$sqliteName ${generateSqliteColumnType()}";
    }
    return _children
        .map((c) => c.generateSqliteColumnDeclarations(indent))
        .join(',\n$indent');
  }

  @override
  String generateSqliteColumnDefinition() {
    if (_children.isEmpty) {
      return "$sqliteName ${generateSqliteColumnType()}";
    }
    return '${_children.map((c) => c.generateSqliteColumnDefinition()).join(',\n')}\n';
  }

  @override
  String generateSqliteUpdateClause(String indent) {
    if (_children.isEmpty) {
      return "$sqliteName=excluded.$sqliteName";
    }
    return _children
        .where((c) => c.mutable)
        .map((c) => c.generateSqliteUpdateClause(indent))
        .join(',\n$indent');
  }

  /// Function to get the field from an object
  @override
  LookupField<T, Object?> get getter => _getter;

  LookupField<T, V> _getter;

  /// Descriptive name of a field
  @override
  String get name => _name;

  String _name;

  /// Name of the field in JSON
  String jsonName;

  /// Name of the corresponding column in SQLite
  String sqliteName;

  /// Name of the corresponding field in SHQL™
  String shqlName;

  /// UI display name (falls back to [name])
  String? displayName;

  /// Description of a field
  String description;

  /// Function to format the field on an object as a presentable string
  FormatField<T> format;

  /// Extra data then displaying the field as part of a formatted output of an entire object
  FormatField<T> formatEx;

  /// Function to get the field from an object for SQLite inserts and updates
  SQLGetter<T> sqliteGetter;

  /// Function to expose the fields as SHQL™ (Small, Handy, Quintessential Language™)
  SHQLGetter<T> shqlGetter;

  /// True if field is part of the primary key
  bool primary;

  /// True if db field is nullable (TODO: should be derived from the getter-type but that doesn't seem to work)
  bool nullable;

  @override
  bool get mutable => _mutable;

  bool _mutable;

  /// True if a field is assigned by the system and should not be prompted for during creation or update
  bool assignedBySystem;

  /// True if field should be part of comparisons
  bool comparable;

  /// Optional prompt suffix to be shown when prompting for this field
  String? prompt;

  final List<FieldBase> _children;

  List<FieldBase> get children => _children;

  // Hack to signify that children are only for db purposes, not for prompting or diffing
  bool childrenForDbOnly;

  // Extra strings that are mapped to null, little Bobby Null we call him.
  List<String> extraNullLiterals;

  /// Function to validate user input for this field
  ValidateInput validateInput;

  /// Whether this field should appear in summary/card views
  bool showInSummary;

  /// Whether this section appears in the detail view
  bool showInDetail;

  static const deepEq = DeepCollectionEquality();
}
