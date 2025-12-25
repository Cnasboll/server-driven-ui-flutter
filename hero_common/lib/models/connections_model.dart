import 'dart:core';

import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/amendable.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';

class ConnectionsModel extends Amendable<ConnectionsModel> {
  ConnectionsModel({this.groupAffiliation, this.relatives});

  ConnectionsModel.from(ConnectionsModel other)
    : this(
        groupAffiliation: other.groupAffiliation,
        relatives: other.relatives,
      );

  ConnectionsModel copyWith({String? groupAffiliation, String? relatives}) {
    return ConnectionsModel(
      groupAffiliation: groupAffiliation ?? this.groupAffiliation,
      relatives: relatives ?? this.relatives,
    );
  }

  @override
  Future<ConnectionsModel> amendWith(Map<String, dynamic>? amendment, {ParsingContext? parsingContext}) async {
    return ConnectionsModel(
      groupAffiliation: _groupAffiliationField.getNullableStringForAmendment(
        this,
        amendment,
      ),
      relatives: _relativesField.getNullableStringForAmendment(this, amendment),
    );
  }

  static ConnectionsModel fromJson(Map<String, dynamic>? json, {ParsingContext? parsingContext}) {
    if (json == null) {
      return ConnectionsModel();
    }
    return ConnectionsModel(
      groupAffiliation: _groupAffiliationField.getNullableString(json),
      relatives: _relativesField.getNullableString(json),
    );
  }

  factory ConnectionsModel.fromRow(Row row) {
    return ConnectionsModel(
      groupAffiliation: _groupAffiliationField.getNullableStringFromRow(row),
      relatives: _relativesField.getNullableStringFromRow(row),
    );
  }

  final String? groupAffiliation;
  final String? relatives;

  static Future<ConnectionsModel> fromPrompt() async {
    var json = await Amendable.promptForJson(staticFields);
    if (json == null || json.length != staticFields.length) {
      return ConnectionsModel();
    }

    return ConnectionsModel.fromJson(json);
  }

  @override
  List<FieldBase<ConnectionsModel>> get fields => staticFields;

  static FieldBase<ConnectionsModel> get _groupAffiliationField => Field.infer(
    (m) => m.groupAffiliation,
    'Group Affiliation',
    'Groups the character is affiliated with wether currently or in the past and if addmittedly or not',
  );

  static final FieldBase<ConnectionsModel> _relativesField = Field.infer(
    (m) => m.relatives,
    'Relatives',
    'A list of the character\'s relatives by blood, marriage, adoption, or pure association',
  );

  static final List<FieldBase<ConnectionsModel>> staticFields = [
    _groupAffiliationField,
    _relativesField,
  ];
}
