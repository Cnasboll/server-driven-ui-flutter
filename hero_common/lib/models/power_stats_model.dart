import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/amendable.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/value_types/percentage.dart';

class PowerStatsModel extends Amendable<PowerStatsModel> {
  PowerStatsModel({
    this.intelligence,
    this.strength,
    this.speed,
    this.durability,
    this.power,
    this.combat,
  });

  PowerStatsModel.from(PowerStatsModel other)
    : this(
        intelligence: other.intelligence,
        strength: other.strength,
        speed: other.speed,
        durability: other.durability,
        power: other.power,
        combat: other.combat,
      );

  PowerStatsModel copyWith({
    Percentage? intelligence,
    Percentage? strength,
    Percentage? speed,
    Percentage? durability,
    Percentage? power,
    Percentage? combat,
  }) {
    return PowerStatsModel(
      intelligence: intelligence ?? this.intelligence,
      strength: strength ?? this.strength,
      speed: speed ?? this.speed,
      durability: durability ?? this.durability,
      power: power ?? this.power,
      combat: combat ?? this.combat,
    );
  }

  @override
  int compareTo(PowerStatsModel other) {
    // Sort by strength, descending first followed by intelligence, speed, durability, power, combat by reversing the comparison
    // to get descending order.
    for (var field in [
      _strengthField,
      _intelligenceField,
      _speedField,
      _durabilityField,
      _powerField,
      _combatField,
    ]) {
      int comparison = field.compareField(other, this);
      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  @override
  Future<PowerStatsModel> amendWith(
    Map<String, dynamic>? amendment, {
    ParsingContext? parsingContext,
  }) async {
    return PowerStatsModel(
      intelligence: _intelligenceField.getPercentageForAmendment(
        this,
        amendment,
        parsingContext: parsingContext?.next(_intelligenceField.name),
      ),
      strength: _strengthField.getPercentageForAmendment(
        this,
        amendment,
        parsingContext: parsingContext?.next(_strengthField.name),
      ),
      speed: _speedField.getPercentageForAmendment(
        this,
        amendment,
        parsingContext: parsingContext?.next(_speedField.name),
      ),
      durability: _durabilityField.getPercentageForAmendment(
        this,
        amendment,
        parsingContext: parsingContext?.next(_durabilityField.name),
      ),
      power: _powerField.getPercentageForAmendment(
        this,
        amendment,
        parsingContext: parsingContext?.next(_powerField.name),
      ),
      combat: _combatField.getPercentageForAmendment(
        this,
        amendment,
        parsingContext: parsingContext?.next(_combatField.name),
      ),
    );
  }

  static PowerStatsModel fromJson(
    Map<String, dynamic>? json, {
    ParsingContext? parsingContext,
  }) {
    if (json == null) {
      return PowerStatsModel();
    }
    return PowerStatsModel(
      intelligence: _intelligenceField.getNullablePercentage(
        json,
        parsingContext: parsingContext?.next(_intelligenceField.name),
      ),
      strength: _strengthField.getNullablePercentage(
        json,
        parsingContext: parsingContext?.next(_strengthField.name),
      ),
      speed: _speedField.getNullablePercentage(
        json,
        parsingContext: parsingContext?.next(_speedField.name),
      ),
      durability: _durabilityField.getNullablePercentage(
        json,
        parsingContext: parsingContext?.next(_durabilityField.name),
      ),
      power: _powerField.getNullablePercentage(
        json,
        parsingContext: parsingContext?.next(_powerField.name),
      ),
      combat: _combatField.getNullablePercentage(
        json,
        parsingContext: parsingContext?.next(_combatField.name),
      ),
    );
  }

  factory PowerStatsModel.fromRow(Row row) {
    return PowerStatsModel(
      intelligence: _intelligenceField.getNullablePercentageFromRow(row),
      strength: _strengthField.getNullablePercentageFromRow(row),
      speed: _speedField.getNullablePercentageFromRow(row),
      durability: _durabilityField.getNullablePercentageFromRow(row),
      power: _powerField.getNullablePercentageFromRow(row),
      combat: _combatField.getNullablePercentageFromRow(row),
    );
  }

  final Percentage? intelligence;
  final Percentage? strength;
  final Percentage? speed;
  final Percentage? durability;
  final Percentage? power;
  final Percentage? combat;

  static Future<PowerStatsModel?> fromPrompt() async {
    var json = await Amendable.promptForJson(staticFields);
    if (json == null || json.length != staticFields.length) {
      return null;
    }

    return PowerStatsModel.fromJson(json);
  }

  /// Subclasses may override to contribute additional fields.
  @override
  List<FieldBase<PowerStatsModel>> get fields => staticFields;

  static FieldBase<PowerStatsModel> get _intelligenceField => Field.infer(
    (m) => m.intelligence?.value,
    "Intelligence",
    '%',
    validateInput: Percentage.validateInput,
    showInSummary: true,
  );

  static FieldBase<PowerStatsModel> get _strengthField => Field.infer(
    (m) => m.strength?.value,
    'Strength',
    '%',
    validateInput: Percentage.validateInput,
    showInSummary: true,
  );

  static FieldBase<PowerStatsModel> get _speedField => Field.infer(
    (m) => m.speed?.value,
    'Speed',
    '%',
    validateInput: Percentage.validateInput,
    showInSummary: true,
  );

  static FieldBase<PowerStatsModel> get _durabilityField => Field.infer(
    (m) => m.durability?.value,
    'Durability',
    '%',
    validateInput: Percentage.validateInput,
    showInSummary: true,
  );

  static FieldBase<PowerStatsModel> get _powerField => Field.infer(
    (m) => m.power?.value,
    'Power',
    '%',
    validateInput: Percentage.validateInput,
    showInSummary: true,
  );

  static FieldBase<PowerStatsModel> get _combatField => Field.infer(
    (m) => m.combat?.value,
    'Combat',
    '%',
    validateInput: Percentage.validateInput,
    showInSummary: true,
  );

  static final List<FieldBase<PowerStatsModel>> staticFields = [
    _intelligenceField,
    _strengthField,
    _speedField,
    _durabilityField,
    _powerField,
    _combatField,
  ];
}
