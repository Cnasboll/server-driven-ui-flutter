import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/utils/json_parsing.dart';
import 'package:hero_common/value_types/conflict_resolver.dart';
import 'package:hero_common/value_types/value_type.dart';

class Weight extends ValueType<Weight> {
  Weight(super.value, super.systemOfUnits);
  Weight.fromPounds(int pounds)
    : this(poundsToKilograms(pounds.toDouble()), SystemOfUnits.imperial);
  Weight.fromKilograms(int kilograms)
    : this(kilograms.toDouble(), SystemOfUnits.metric);

  static final Weight zero = Weight(0, SystemOfUnits.imperial);

  static Weight fromRow(FieldBase fieldBase, Row row) {
    var (kilograms, systemOfUnits) = ValueType.fromRow(
      _valueField,
      _systemOfUnitsField,
      row,
    );
    return Weight(kilograms, systemOfUnits);
  }

  static Weight parse(String input) {
    var (value, error) = tryParse(input);
    if (error != null) {
      throw FormatException(error);
    }
    if (value == null) {
      throw FormatException('Could not parse weight: $input');
    }
    return value;
  }

  static (bool, String?) validateinput(String? input) {
    var (_, error) = tryParse(input);
    return (error == null, error);
  }
  
  /// Parse a weight string such as "210 lb", "95 kg", "18 tons", "90,0000 tons" or just "95"
  /// "- lb" also represents zero, apparently
  static (Weight?, String?) tryParse(String? input) {
    if (input == null) {
      // Null is not an error, it just means no information provided
      return (null, null);
    }

    final s = input.trim();
    if (s.isEmpty) {
      return (null, 'Empty weight string');
    }

    final weightRegex = RegExp(
      r'''^\s*(\d+(\,\d+)?|-)?\s*(lb|kg|tons)?\s*$''',
      caseSensitive: false,
    );

    final match = weightRegex.firstMatch(s);
    if (match != null) {
      // A dash means zero, apparently, handled by specialNullCoalesce()
      var s1 = specialNullCoalesce(match.group(1));
      // Filter out commas from numbers like "90,000" for Godzilla's weight
      final value = s1 == null ? 0 : int.tryParse(s1.replaceAll(",", ""));
      if (value != null) {
        var unit = match.group(3);
        if (unit == 'lb') {
          return (Weight.fromPounds(value), null);
        }
        if (unit == 'tons') {
          return (Weight.fromKilograms(value * 1000), null);
        }
        return (Weight.fromKilograms(value), null);
      }
    }

    return (null, 'Could not parse weight: $input');
  }

  static Future<Weight> parseList(
    List<String>? valueInVariousUnits, {
    ParsingContext? parsingContext,
  }) async {
    var (value, error) = await tryParseList(
      valueInVariousUnits,
      parsingContext,
    );
    if (error != null) {
      throw FormatException(error);
    }
    return value ?? Weight(0, SystemOfUnits.imperial);
  }

  static ConflictResolver<Weight>? conflictResolver;
  static Future<(Weight?, String?)> tryParseList(
    List<String>? valueVariousUnits,
    ParsingContext? parsingContext,
  ) async {
    return ValueType.tryParseList(
      valueVariousUnits,
      "weight",
      tryParse,
      conflictResolver: conflictResolver,
      parsingContext: parsingContext,
    );
  }

  static final RegExp largeIntegerFormatRegexp = RegExp(
    r'(\d{1,3})(?=(\d{3})+(?!\d))',
  );
  String largeIntegerToString(int value) {
    return value.toString().replaceAllMapped(
      largeIntegerFormatRegexp,
      (Match match) => '${match[1]},',
    );
  }

  @override
  String toString() {
    if (isImperial) {
      if (value == 0.0) {
        return "- lb"; // Dash means zero, apparently
      }
      return "$wholePounds lb";
    }
    if (isMetric) {
      if (value > 1000 && value % 1000 == 0) {
        var tons = value / 1000;

        return "${largeIntegerToString(tons.round())} tons";
      }

      return "$wholeKilograms kg";
    }
    return '<unknown>';
  }

  static final double kilosgramsPerPound = 0.45359237;

  static double poundsToKilograms(double pounds) {
    return pounds * kilosgramsPerPound;
  }

  static double kilogramsToPounds(double kilograms) {
    return kilograms / kilosgramsPerPound;
  }

  int get wholePounds => (kilogramsToPounds(value)).round();
  int get wholeKilograms => value.floor();

  @override
  Weight cloneMetric() {
    return Weight.fromKilograms(wholeKilograms);
  }

  @override
  Weight cloneImperial() {
    return Weight.fromPounds(wholePounds);
  }

  @override
  Weight integralFromOtherSystem(int integralValue) {
    if (isMetric) {
      // Interpret integralValue as whole pounds
      return Weight.fromPounds(integralValue);
    }
    // Interpret integralValue as whole kilograms
    return Weight.fromKilograms(integralValue);
  }

  @override
  List<FieldBase<ValueType<Weight>>> get fields => staticFields;

  static final FieldBase<ValueType<Weight>> _valueField = Field.infer(
    (h) => h.value,
    "Weight (kg)",
    jsonName: "weight-kilograms",
    sqliteName: "weight_kg",
    shqlName: "kg",
    'The character\'s weight of in kilograms',
    // Unknown weights are stored as 0.0 (Weight.zero). Expose as null in SHQL™
    // so filter predicates like "weight.kg < threshold" don't match unknowns.
    shqlGetter: (h) => h.value > 0 ? h.value : null,
    nullable: false,
  );

  static final FieldBase<ValueType<Weight>> _systemOfUnitsField = Field.infer(
    (h) => h.systemOfUnits,
    "Weight System of Units",
    jsonName: "weight-system-of-units",
    sqliteName: "weight_system_of_units",
    shqlName: "system_of_units",
    'The source system of units for the weight value (${SystemOfUnits.values.map((e) => e.name).join(" or ")})',
    sqliteGetter: (h) => h.systemOfUnits.name,
    shqlGetter: (h) => h.systemOfUnits.index,
    nullable: false,
  );

  static final List<FieldBase<ValueType<Weight>>> staticFields = [
    _valueField,
    _systemOfUnitsField,
  ];
}
