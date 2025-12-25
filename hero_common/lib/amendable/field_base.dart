import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/value_types/percentage.dart';

typedef Row = Map<String, dynamic>;

abstract class FieldBase<T> {
  Future<bool> promptForJson(Map<String, dynamic> json, {String? crumbtrail});
  Future<void> promptForAmendmentJson(
    T original,
    Map<String, dynamic> amendment, {
    String? crumbtrail,
  });
  bool validateAmendment(T lhs, T rhs);
  bool matches(T t, String query);
  void formatField(T t, StringBuffer sb, {String? crumbtrail});
  bool diff(T lhs, T rhs, StringBuffer sb, {String? crumbtrail});
  int compareField(T lhs, T rhs);
  int? getIntForAmendment(T t, Map<String, dynamic>? amendment);
  int getIntFromJson(Map<String, dynamic>? json, int defaultValue);
  int? getNullableInt(Map<String, dynamic>? json);
  int getIntFromRow(Row row, int defaultValue);
  int? getNullableIntFromRow(Row row);
  Percentage? getPercentageForAmendment(T t, Map<String, dynamic>? amendment, {ParsingContext? parsingContext});
  Percentage getPercentageFromJson(Map<String, dynamic>? json, int defaultValue, {ParsingContext? parsingContext});
  Percentage? getNullablePercentage(Map<String, dynamic>? json, {ParsingContext? parsingContext});
  Percentage getPercentageFromRow(Row row, int defaultValue);
  Percentage? getNullablePercentageFromRow(Row row);
  double getFloatFromRow(Row row, double defaultValue);
  double? getNullableFloatFromRow(Row row);
  bool getBoolFromRow(Row row, bool defaultValue);
  bool? getNullableBoolFromRow(Row row);
  String getStringForAmendment(T t, Map<String, dynamic>? amendment);
  String? getNullableStringForAmendment(T t, Map<String, dynamic>? amendment);
  String? getNullableString(Map<String, dynamic>? json);
  String getString(Map<String, dynamic>? json, String defaultValue);
  Map<String, dynamic>? getJson(Map<String, dynamic>? json);
  String? getNullableStringFromRow(Row row);
  String getStringFromRow(Row row, String defaultValue);
  List<String> getStringListFromJsonForAmendment(
    T t,
    Map<String, dynamic>? amendment,
  );
  List<String>? getNullableStringListFromJsonForAmendment(
    T t,
    Map<String, dynamic>? amendment,
  );
  List<String> getStringList(
    Map<String, dynamic>? json,
    List<String> defaultValue,
  );
  List<String>? getNullableStringList(Map<String, dynamic>? json);
  List<String> getStringListFromRow(Row row, List<String> defaultValue);
  List<String>? getNullableStringListFromRow(Row row);
  DateTime getDateTimeFromRow(Row row, DateTime defaultValue);
  DateTime? getNullableDateTimeFromRow(Row row);
  E getEnumForAmendment<E extends Enum>(
    T t,
    Iterable<E> enumValues,
    Map<String, dynamic>? amendment,
  );
  E getEnum<E extends Enum>(
    Iterable<E> enumValues,
    Map<String, dynamic>? amendment,
    E defaultValue,
  );
  E getEnumFromRow<E extends Enum>(
    Iterable<E> enumValues,
    Row row,
    E defaultValue,
  );
  String sqliteQualifier();
  String generateSqliteColumnType();
  List<Object?> sqliteProps(T t);
  String generateSQLiteInsertColumnPlaceholders();
  String generateSqliteColumnNameList(String indent);
  String generateSqliteColumnDeclarations(String indent);
  String generateSqliteColumnDefinition();
  String generateSqliteUpdateClause(String indent);
  Object? Function(T) get getter;

  /// Descriptive name of a field
  String get name;

  /// True if field is mutable
  bool get mutable;
}
