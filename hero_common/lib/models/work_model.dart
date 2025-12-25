import 'dart:core';

import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/amendable.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';

class WorkModel extends Amendable<WorkModel> {
  WorkModel({this.occupation, this.base});

  WorkModel.from(WorkModel other)
    : this(occupation: other.occupation, base: other.base);

  WorkModel copyWith({String? occupation, String? base}) {
    return WorkModel(
      occupation: occupation ?? this.occupation,
      base: base ?? this.base,
    );
  }

  @override
  Future<WorkModel> amendWith(
    Map<String, dynamic>? amendment, {
    ParsingContext? parsingContext,
  }) async {
    return WorkModel(
      occupation: _occupationField.getNullableStringForAmendment(
        this,
        amendment,
      ),
      base: _baseField.getNullableStringForAmendment(this, amendment),
    );
  }

  static WorkModel fromJson(
    Map<String, dynamic>? json, {
    ParsingContext? parsingContext,
  }) {
    if (json == null) {
      return WorkModel();
    }
    return WorkModel(
      occupation: _occupationField.getNullableString(json),
      base: _baseField.getNullableString(json),
    );
  }

  factory WorkModel.fromRow(Row row) {
    return WorkModel(
      occupation: _occupationField.getNullableStringFromRow(row) ?? "",
      base: _baseField.getNullableStringFromRow(row) ?? "",
    );
  }

  final String? occupation;
  final String? base;

  static Future<WorkModel> fromPrompt() async {
    var json = await Amendable.promptForJson(staticFields);
    if (json == null || json.length != staticFields.length) {
      return WorkModel();
    }

    return WorkModel.fromJson(json);
  }

  @override
  List<FieldBase<WorkModel>> get fields => staticFields;

  static FieldBase<WorkModel> get _occupationField => Field.infer(
    (m) => m.occupation,
    'Occupation',
    'Occupation of the character',
  );

  static FieldBase<WorkModel> get _baseField => Field.infer(
    (m) => m.base,
    'Base',
    'A place where the character works or lives or hides rather frequently',
  );

  static final List<FieldBase<WorkModel>> staticFields = [
    _occupationField,
    _baseField,
  ];
}
