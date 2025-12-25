import 'package:test/test.dart';
import 'package:hero_common/value_types/height.dart';

void main() {
  test('a dash means zero feet and zero inches', () {
    final h = Height.parse("-");
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 0);
    expect(inches, 0);
    expect(h.wholeCentimeters, 0);
    expect(h.isImperial, true);
    expect(h.toString(), "-");
  });

  test(
    "For the suphero Dagger, 'Shaker Heights, Ohio' means zero feet and zero inches",
    () {
      final h = Height.parse("Shaker Heights, Ohio");
      var (feet, inches) = h.wholeFeetAndWholeInches;
      expect(feet, 0);
      expect(inches, 0);
      expect(h.wholeCentimeters, 0);
      expect(h.isImperial, true);
      expect(h.toString(), "-");
    },
  );

  test('parse imperial shorthand', () {
    final h = Height.parse("6'2\"");
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(h.wholeCentimeters, 188);
    expect(h.toString(), "6'2\"");
  });

  test('parse imperial shorthand with space', () {
    final h = Height.parse("6 '2 \"");
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(h.wholeCentimeters, 188);
    expect(h.toString(), "6'2\"");
  });

  test('parse imperial verbose', () {
    final h = Height.parse('6 ft 2 in');
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(h.toString(), "6'2\"");
  });

  /// The White Queen with id "241" has a height of 5'10' instead of the more usual 5'10", treat it the same
  test('Parse White Queen Height', () {
    final h = Height.parse("5'10'");
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 5);
    expect(inches, 10);
    expect(h.toString(), "5'10\"");
  });

  test('parse cm', () {
    final h = Height.parse('188 cm');
    expect(h.wholeCentimeters, 188);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(h.toString(), "188 cm");
  });

  test('parse cm compact', () {
    final h = Height.parse('188cm');
    expect(h.wholeCentimeters, 188);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(h.toString(), "188 cm");
  });

  test('parse integer asumed cm', () {
    final h = Height.parse('188');
    expect(h.wholeCentimeters, 188);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(h.toString(), "188 cm");
  });

  test('parse integral m', () {
    final h = Height.parse('2 m');
    expect(h.wholeCentimeters, 200);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 7);
    expect(h.toString(), "200 cm");
  });

  test('parse integer assumed m', () {
    final h = Height.parse('2');
    expect(h.wholeCentimeters, 200);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 7);
    expect(h.toString(), "200 cm");
  });

  test('parse meters', () {
    final h = Height.parse('1.88 m');
    expect(h.wholeCentimeters, 188);
    expect(h.toString(), "188 cm");
  });

  test('parse meters compact', () {
    final h = Height.parse('1.88m');
    expect(h.wholeCentimeters, 188);
    expect(h.toString(), "188 cm");
  });

  test('parse double assumed meters', () {
    final h = Height.parse('1.88');
    expect(h.wholeCentimeters, 188);
    expect(h.toString(), "188 cm");
  });

  test('parse list with corresponding values in different systems', () async {
    final imp = await Height.parseList(['6\'2"', '188 cm']);
    var (feet, inches) = imp.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(imp.toString(), '6\'2"');

    final impWithOtherMetric = await Height.parseList(['6\'2"', '189 cm']);
    (feet, inches) = impWithOtherMetric.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(impWithOtherMetric.toString(), '6\'2"');

    final redundantImp = await Height.parseList(['6\'2"', '188 cm', '6 ft 2 in']);
    (feet, inches) = redundantImp.wholeFeetAndWholeInches;
    expect(feet, 6);
    expect(inches, 2);
    expect(redundantImp.toString(), '6\'2"');

    final metric = await Height.parseList(['188 cm', '6\'2"']);
    expect(metric.wholeCentimeters, 188);
    expect(metric.toString(), "188 cm");

    final redundantMetric = await Height.parseList(['188 cm', '6\'2"', "1.88"]);
    expect(redundantMetric.wholeCentimeters, 188);
    expect(redundantMetric.toString(), "188 cm");
  });

  test('parse Ymir meters', () async {
    final h = await Height.parse("304.8 meters");
    expect(h.wholeCentimeters, 30480);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 1000);
    expect(inches, 0);
    expect(h.toString(), "304.8 meters");
  });

  test('parse Ymir height infer 1000 feet', () async {
    // We infer that 1000 means feet here
    final h = await Height.parseList(["1000", "304.8 meters"]);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 1000);
    expect(inches, 0);
    expect(h.wholeCentimeters, 30480);
    expect(h.toString(), "1000'0\"");
  });

  test('parse Ymir height in different order still infer 1000 feet', () async {
    // We infer that 1000 means feet here
    final h = await Height.parseList(["304.8 meters", "1000"]);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 1000);
    expect(inches, 0);
    expect(h.wholeCentimeters, 30480);
    expect(h.toString(), "304.8 meters");
  });

  test('can display Anti-Monitor\'s 200 ft in cm to 61.0 m', () {
    final h = Height.parse('6096 cm');
    expect(h.wholeCentimeters, 6096);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 200);
    expect(inches, 0);
    expect(h.toString(), "61.0 meters");
  });

  test('parse Anti-Montitor height', () async {
    final h = await Height.parseList(["200", "61.0 meters"]);
    var (feet, inches) = h.wholeFeetAndWholeInches;
    expect(feet, 200);
    expect(inches, 0);
    expect(h.wholeMeters, 61);
    expect(h.toString(), "200'0\"");
  });

  test('parse with in conflicting values in different systems', () {
    expect(
      () => Height.parseList(['6\'2"', '190 cm']),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message ==
                  "Conflicting height information: metric '190 cm' (parsed from '190 cm') corresponds to '6'3\"' after converting back to imperial -- expecting '188 cm' in order to match first value of '6'2\"' (parsed from '6'2\"')",
        ),
      ),
    );
  });

  test('parse list with conflicting values in same system', () {
    expect(
      () => Height.parseList(['6\'2"', '6 feet 3']),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message ==
                  "Conflicting height information: '6'3\"' (parsed from '6 feet 3') doesn't match first value '6'2\"' (parsed from '6'2\"')",
        ),
      ),
    );
  });
}
