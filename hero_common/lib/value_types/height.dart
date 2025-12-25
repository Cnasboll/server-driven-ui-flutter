import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/utils/json_parsing.dart';
import 'package:hero_common/value_types/conflict_resolver.dart';
import 'package:hero_common/value_types/value_type.dart';

class Height extends ValueType<Height> {
  Height(super.value, super.systemOfUnits);

  Height.fromFeetAndInches(int feet, int inches)
    : this(feetAndInchesToMeters(feet, inches), SystemOfUnits.imperial);
  Height.fromCentimeters(int centimeters)
    : this(centimeters.toDouble() / 100.0, SystemOfUnits.metric);
  Height.fromMeters(int meters) : this(meters.toDouble(), SystemOfUnits.metric);

  static final Height zero = Height(0, SystemOfUnits.imperial);

  static Height fromRow(FieldBase fieldBase, Row row) {
    var (metres, systemOfUnits) = ValueType.fromRow(
      _valueField,
      _systemOfUnitsField,
      row,
    );
    return Height(metres, systemOfUnits);
  }

  static Height parse(String input) {
    var (value, error) = tryParse(input);
    if (error != null) {
      throw FormatException(error);
    }
    if (value == null) {
      throw FormatException('Could not parse height: $input');
    }
    return value;
  }

  static final String daggerHeight = "Shaker Heights, Ohio";

  static (bool, String?) validateinput(String? input) {
    var (_, error) = tryParse(input);
    return (error == null, error);
  }

  /// Parse a height string
  ///
  /// Recognises common imperial forms like:
  /// - 6'2"  (with single-quote feet and double-quote inches)
  /// - 6'  or 6 ft
  /// - 6 ft 2 in
  /// and metric forms like:
  /// - 188 cm
  /// - 188cm
  /// - 188  (assumed to be cm if no unit given)
  /// - 1.88 m
  /// - 1.88
  /// A dash means zero, apparently
  /// "Dagger" has height "Shaker Heights, Ohio" which we also interpret as zero for consistency
  static (Height?, String?) tryParse(String? input) {
    if (input == null) {
      // Null is not an error, it just means no information provided
      return (null, null);
    }
    final String s = input.trim();
    if (s.isEmpty) {
      return (null, 'Empty height string');
    }

    if (specialNullCoalesce(s, extraNullLiterals: [daggerHeight]) == null) {
      // In the superheroapi, Dash "-" means zero, apparently
      // Also "Dagger" has height "Shaker Heights, Ohio" which we interpret as zero for consistency
      return (Height.fromFeetAndInches(0, 0), null);
    }

    // Try imperial shorthand: 6'2" or 6'2 or 6' 2" or even 5'10' which is the height of White Queen in api!
    final imperialRegex = RegExp(
      r'''^\s*(\d+)\s*'\s*(\d+)?\s*(?:"|'|in)?\s*$''',
    );
    var match = imperialRegex.firstMatch(s);
    if (match != null) {
      final feet = int.tryParse(match.group(1) ?? '');
      final inches = int.tryParse(match.group(2) ?? '') ?? 0;
      if (feet != null) {
        return (Height.fromFeetAndInches(feet, inches), null);
      }
    }

    // Try verbose imperial: 6 ft 2 in, 6 feet 2 inches
    final imperialVerbose = RegExp(
      r'''^\s*(\d+)\s*(?:ft|feet)\s*(\d+)?\s*(?:in|inch|inches)?\s*$''',
      caseSensitive: false,
    );
    match = imperialVerbose.firstMatch(s);
    if (match != null) {
      final feet = int.tryParse(match.group(1) ?? '');
      final inches = int.tryParse(match.group(2) ?? '') ?? 0;
      if (feet != null) {
        return (Height.fromFeetAndInches(feet, inches), null);
      }
    }

    // Try integral metric or imperial: 6 feet, 188 cm, 2m or 188 e.g. with or without unit or spaces (assumed cm for values > 2 if no unit
    final integralMetricRegex = RegExp(
      r'''^\s*(\d+)\s*(ft|feet|cm|m|meters)?\s*$''',
      caseSensitive: false,
    );

    match = integralMetricRegex.firstMatch(s);
    if (match != null) {
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null) {
        var unit = match.group(2);
        if (unit == null) {
          // No unit given, assume m if value less than 3, otherwise cm
          if (value > 2) {
            unit = 'cm';
          } else {
            unit = 'm';
          }
        }
        if (unit == 'ft' || unit == 'feet') {
          return (Height.fromFeetAndInches(value, 0), null);
        }

        if (unit == 'm') {
          return (Height.fromMeters(value), null);
        }
        return (Height.fromCentimeters(value), null);
      }
    }

    // Try metric meters: 1.88 m with our without unit or spaces
    final mRegex = RegExp(
      r'''^\s*(\d+(?:\.\d+)?)\s*(m|meters)?\s*$''',
      caseSensitive: false,
    );
    match = mRegex.firstMatch(s);
    if (match != null) {
      final meters = double.tryParse(match.group(1) ?? '');
      if (meters != null) {
        final centimeters = (meters * 100).round();
        return (Height.fromCentimeters(centimeters), null);
      }
    }

    return (null, 'Could not parse height: $input');
  }

  static Future parseList(
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
    return value ?? zero;
  }

  static ConflictResolver<Height>? conflictResolver;
  static Future<(Height?, String?)> tryParseList(
    List<String>? valueVariousUnits,
    ParsingContext? parsingContext,
  ) async {
    return ValueType.tryParseList(
      valueVariousUnits,
      "height",
      tryParse,
      conflictResolver: conflictResolver,
      parsingContext: parsingContext,
    );
  }

  @override
  String toString() {
    if (isImperial) {
      if (value == 0.0) {
        return "-"; // Dash means zero, apparently
      }
      final (feet, inches) = metersToFeetAndInches(value);
      return "$feet'${inches.round()}\"";
    }
    if (isMetric) {
      // 2 digit+ meters with one decimal place e.g. 60.96 meters are formatted as "60.1 meters"
      // for 200 feet for "Anti-Monitor". Why oh why are we doing all this?
      if (value > 10) {
        var rounded = (value * 10).round();
        return "${(rounded / 10).toStringAsFixed(1)} meters";
      }

      if (value > 2 && value.round() == value) {
        // Whole number of metres (spelled "meters" in US English)
        return "${(value).round()} meters";
      }

      // Whole number of centimeters
      return "${(value * 100).round()} cm";
    }
    return '<unknown>';
  }

  static const double metersPerInch = 0.0254;
  static const double inchesPerFeet = 12.0;

  static double feetAndInchesToMeters(int feet, int inches) {
    double totalInches = (feet * inchesPerFeet) + inches;
    return totalInches * metersPerInch;
  }

  int get wholeCentimeters => (value * 100.0).round();
  int get wholeMeters => value.round();

  (int, int) get wholeFeetAndWholeInches {
    var (feet, inches) = metersToFeetAndInches(value);
    return (feet, inches.round());
  }

  static (int, double) metersToFeetAndInches(double meters) {
    final double totalInches = meters / metersPerInch;
    final double totalFeet = totalInches / inchesPerFeet;
    final double inches = totalInches % inchesPerFeet;
    return (totalFeet.floor(), inches);
  }

  @override
  Height cloneMetric() {
    // Convert meters to 3 significant digits (this destroys precision if value is imperial)
    return Height(withThreeSignificantDigits(value), SystemOfUnits.metric);
  }

  static double withThreeSignificantDigits(double d) {
    return d;
  }

  @override
  Height cloneImperial() {
    // Converts feet and inches to a round number of inches (this destroys precision if value is metric)
    var (feet, inches) = wholeFeetAndWholeInches;
    return Height(
      // Round to meters with three significant digits
      withThreeSignificantDigits(feetAndInchesToMeters(feet, inches)),
      SystemOfUnits.imperial,
    );
  }

  @override
  Height integralFromOtherSystem(int integralValue) {
    if (isMetric) {
      // Interpret integralValue as whole feet
      return Height.fromFeetAndInches(integralValue, 0);
    }

    if (value > 2) {
      // Interpret integralValue >= 3 as whole centimeters
      return Height.fromCentimeters(integralValue);
    }

    // Interpret integralValue <= 2 as whole meters
    return Height.fromMeters(integralValue);
  }

  @override
  List<FieldBase<ValueType<Height>>> get fields => staticFields;

  static final FieldBase<ValueType<Height>> _valueField = Field.infer(
    (h) => h.value,
    "Height (m)",
    jsonName: "height-metres",
    sqliteName: "height_m",
    shqlName: "m",
    'The character\'s height in metres',
    // Unknown heights are stored as 0.0 (Height.zero). Expose as null in SHQL™
    // so filter predicates like "height.m < threshold" don't match unknowns.
    shqlGetter: (h) => h.value > 0 ? h.value : null,
    nullable: false,
  );

  static final FieldBase<ValueType<Height>> _systemOfUnitsField = Field.infer(
    (h) => h.systemOfUnits,
    "Height System of Units",
    jsonName: "height-system-of-units",
    sqliteName: "height_system_of_units",
    shqlName: "system_of_units",
    'The source system of units for height value (${SystemOfUnits.values.map((e) => e.name).join(" or ")})',
    sqliteGetter: (h) => h.systemOfUnits.name,
    shqlGetter: (h) => h.systemOfUnits.index,
    nullable: false,
  );

  static final List<FieldBase<ValueType<Height>>> staticFields = [
    _valueField,
    _systemOfUnitsField,
  ];
}
