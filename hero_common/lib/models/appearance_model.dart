import 'dart:core';

import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/amendable.dart';
import 'package:hero_common/value_types/weight.dart';

enum Gender {
  unknown,
  ambiguous,
  male,
  female,
  nonBinary,
  wontSay;

  String get displayName => switch (this) {
    unknown => 'Unknown',
    ambiguous => 'Ambiguous',
    male => 'Male',
    female => 'Female',
    nonBinary => 'Non-Binary',
    wontSay => "Won't Say",
  };

  static List<String> get displayNames =>
      values.map((e) => e.displayName).toList();
}

class AppearanceModel extends Amendable<AppearanceModel> {
  AppearanceModel({
    this.gender = Gender.unknown,
    this.race,
    Height? height,
    Weight? weight,
    this.eyeColor,
    this.hairColor,
  }) : height = height ?? Height.zero,
       weight = weight ?? Weight.zero;

  AppearanceModel.from(AppearanceModel other)
    : this(
        gender: other.gender,
        race: other.race,
        height: other.height,
        weight: other.weight,
        eyeColor: other.eyeColor,
        hairColor: other.hairColor,
      );

  AppearanceModel copyWith({
    Gender? gender,
    String? race,
    Height? height,
    Weight? weight,
    String? eyeColor,
    String? hairColor,
  }) {
    return AppearanceModel(
      gender: gender ?? this.gender,
      race: race ?? this.race,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      eyeColor: eyeColor ?? this.eyeColor,
      hairColor: hairColor ?? this.hairColor,
    );
  }

  @override
  Future<AppearanceModel> amendWith(
    Map<String, dynamic>? amendment, {
    ParsingContext? parsingContext,
  }) async {
    return AppearanceModel(
      gender: _genderField.getEnumForAmendment<Gender>(
        this,
        Gender.values,
        amendment,
      ),
      race: _raceField.getNullableStringForAmendment(this, amendment),
      height: await Height.parseList(
        _heightField.getNullableStringListFromJsonForAmendment(this, amendment),
        parsingContext: parsingContext?.next(_heightField.name),
      ),
      weight: await Weight.parseList(
        _weightField.getNullableStringListFromJsonForAmendment(this, amendment),
        parsingContext: parsingContext?.next(_weightField.name),
      ),
      eyeColor: _eyeColourField.getNullableStringForAmendment(this, amendment),
      hairColor: _hairColorField.getNullableStringForAmendment(this, amendment),
    );
  }

  static Future<AppearanceModel> fromJson(
    Map<String, dynamic>? json, {
    ParsingContext? parsingContext,
  }) async {
    if (json == null) {
      return AppearanceModel(gender: Gender.unknown);
    }
    return AppearanceModel(
      gender: _genderField.getEnum<Gender>(Gender.values, json, Gender.unknown),
      race: _raceField.getNullableString(json),
      height: await Height.parseList(
        _heightField.getNullableStringList(json),
        parsingContext: parsingContext?.next(_heightField.name),
      ),
      weight: await Weight.parseList(
        _weightField.getNullableStringList(json),
        parsingContext: parsingContext?.next(_weightField.name),
      ),
      eyeColor: _eyeColourField.getNullableString(json),
      hairColor: _hairColorField.getNullableString(json),
    );
  }

  factory AppearanceModel.fromRow(Row row) {
    return AppearanceModel(
      gender: _genderField.getEnumFromRow(Gender.values, row, Gender.unknown),
      race: _raceField.getNullableStringFromRow(row),
      height: Height.fromRow(_heightField, row),
      weight: Weight.fromRow(_weightField, row),
      eyeColor: _eyeColourField.getNullableStringFromRow(row),
      hairColor: _hairColorField.getNullableStringFromRow(row),
    );
  }

  final Gender gender;
  final String? race;
  final Height height;
  final Weight weight;
  final String? eyeColor;
  final String? hairColor;

  static Future<AppearanceModel> fromPrompt() async {
    var json = await Amendable.promptForJson(staticFields);
    if (json == null || json.length != staticFields.length) {
      return AppearanceModel();
    }

    return AppearanceModel.fromJson(json);
  }

  bool get isMale => gender == Gender.male;
  int get genderComparisonFactor => isMale ? 1 : -1;

  @override
  int compareTo(AppearanceModel other) {
    // Sort by non-male first and male second
    // as males are always weaker than everone else who are equal.
    int comparison = genderComparisonFactor.compareTo(
      other.genderComparisonFactor,
    );

    if (comparison != 0) {
      return comparison;
    }

    // Never sort appearances by race as that would be discriminatory, but by height descending (as tall heroes always have
    // an advantage in all areas of life and herohood),
    comparison = _heightField.compareField(other, this);

    if (comparison != 0) {
      return comparison;
    }

    // Sort other fields ascending
    for (var field in [_weightField, _eyeColourField, _hairColorField]) {
      comparison = field.compareField(this, other);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }

  /// Subclasses may override to contribute additional fields.
  @override
  List<FieldBase<AppearanceModel>> get fields => staticFields;

  static final FieldBase<AppearanceModel> _genderField = Field.infer(
    (m) => m.gender,
    "Gender",
    Gender.values.map((e) => e.name).join(', '),
    format: (m) => (m.gender.name).toString(),
    sqliteGetter: (m) => (m.gender.name),
    shqlGetter: (m) => (m.gender.index),
    nullable: false,
  );

  static final FieldBase<AppearanceModel> _raceField = Field.infer(
    (m) => m.race,
    "Race",
    "Species in Latin or English",
    showInSummary: true,
  );

  static FieldBase<AppearanceModel> get _heightField => Field.infer(
    (m) => m.height,
    "Height",
    'Height in centimeters and / or feet and inches',
    // Note that the database columns are height_m and height_system_of_units for presentation, so mapped to TWO columns
    // we don't STORE the string "6'2" but the numeric value 1.8796 and the systemOfUnits enum value "imperial" to document the source
    // for UI formatting
    prompt:
        '. For multiple representations, enter a list in json format e.g. ["6\'2\\"", "188 cm"] or a single value like \'188 cm\', \'188\' or \'1.88\' (meters) without surrounding \'',
    children: Height.staticFields,
    childrenForDbOnly: true,
    nullable: false,
    validateInput: Height.validateinput
  );

  static FieldBase<AppearanceModel> get _weightField => Field.infer(
    (m) => m.weight,
    "Weight",
    'Weight in kilograms and / or pounds',
    // Note that the database columns are weight_kg and weight_system_of_units for presentation, so mapped to TWO columns
    // we don't STORE "210 lb" but the numeric value 95.2543977 and the systemOfUnits enum value "imperial" to document the source
    // for UI formatting
    prompt:
        '. For multiple representations, enter a list in json format e.g. ["210 lb", "95 kg"] or a single value like \'95 kg\' or \'95\' (kilograms) without surrounding \'',
    children: Weight.staticFields,
    childrenForDbOnly: true,
    nullable: false,
    validateInput: Weight.validateinput
  );

  static final FieldBase<AppearanceModel> _eyeColourField = Field.infer(
    (m) => m.eyeColor,
    "Eye Colour", // British spelling in db and in UI as we're in Europe
    jsonName: "eye-color",
    'The character\'s eye color of the most recent appearance',
  );

  static final FieldBase<AppearanceModel> _hairColorField = Field.infer(
    (m) => m.hairColor,
    "Hair Colour", // British spelling in db and in UI as we're in Europe
    jsonName: "hair-color",
    'The character\'s hair color of the most recent appearance',
  );

  static final List<FieldBase<AppearanceModel>> staticFields = [
    _genderField,
    _raceField,
    _heightField,
    _weightField,
    _eyeColourField,
    _hairColorField,
  ];
}
