import 'package:test/test.dart';
import 'package:hero_common/value_types/weight.dart';

void main() {
  test('a dash means zero', () {
    final w = Weight.parse("- lb");
    expect(w.wholePounds, 0);
    expect(w.wholeKilograms, 0);
    expect(w.isImperial, true);
    expect(w.toString(), "- lb");
  });

  test('parse imperial', () {
    final w = Weight.parse("210 lb");
    expect(w.wholePounds, 210);
    expect(w.toString(), "210 lb");
  });

  test('parse imperial', () {
    final w = Weight.parse("210 lb");
    expect(w.wholePounds, 210);
    expect(w.toString(), "210 lb");
  });

  test(
    'parse 210 and 209 lb are both  95 kg verifying source data is ambiguous af',
    () {
      final lb210 = Weight.fromPounds(210);
      final lb209 = Weight.fromPounds(209);
      // It seesms like the api converts pounds to kilograms and rounds DOWN instead of to nearest
      expect(lb210.wholeKilograms, 95);
      expect(lb209.wholeKilograms, 94);
    },
  );

  test('parse imperial compact', () {
    final w = Weight.parse("210lb");
    expect(w.wholePounds, 210);
    expect(w.toString(), "210 lb");
  });

  test('parse kg', () {
    final w = Weight.parse('95 kg');
    expect(w.wholeKilograms, 95);
    expect(w.asImperial().wholePounds, 209);
    expect(w.toString(), "95 kg");
  });

  test('parse kg compact', () {
    final w = Weight.parse('95kg');
    expect(w.wholeKilograms, 95);
    expect(w.toString(), "95 kg");
  });

  test('parse integer assumed kg', () {
    final w = Weight.parse('95');
    expect(w.wholeKilograms, 95);
    expect(w.toString(), "95 kg");
  });

  test('parse Fin Fang Foom weight in tonnes', () {
    final w = Weight.parse('18 tons');
    expect(w.wholeKilograms, 18000);
    expect(w.toString(), "18 tons");
  });

  test('parse Godzilla weight in tonnes', () {
    final w = Weight.parse('90,000 tons');
    expect(w.wholeKilograms, 90000000);
    expect(w.toString(), "90,000 tons");
  });

  test('parse list with corresponding values in different systems', () async {
    final imp = await Weight.parseList(['209 lb', '95 kg']);
    expect(imp.wholePounds, 209);
    expect(imp.toString(), "209 lb");

    final imp2 = await Weight.parseList(['210 lb', '95 kg']);
    expect(imp2.wholePounds, 210);
    expect(imp2.toString(), "210 lb");

    // Note that 95 kgs can correspond to both 209 or 210 pounds
    final metric = await Weight.parseList(['95 kg', '209 lb']);
    expect(metric.wholeKilograms, 95);
    expect(metric.toString(), "95 kg");

    final metric2 = await Weight.parseList(['95 kg', '210 lb']);
    expect(metric2.wholeKilograms, 95);
    expect(metric2.toString(), "95 kg");

    final metric3 = await Weight.parseList(['95 kg', '210 lb', '209 lb']);
    expect(metric3.wholeKilograms, 95);
    expect(metric3.toString(), "95 kg");

    final redundantMetric = await Weight.parseList(['95 kg', '209 lb', "95"]);
    expect(redundantMetric.wholeKilograms, 95);
    expect(redundantMetric.toString(), "95 kg");

    final moreImperial = await Weight.parseList(["155 lb", "70 kg"]);
    expect(moreImperial.wholePounds, 155);
    expect(moreImperial.toString(), "155 lb");
  });

  test('parse with in conflicting values in different systems', () {
    expect(
      () => Weight.parseList(['210 lb', '94 kg']),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message ==
                  "Conflicting weight information: metric '94 kg' (parsed from '94 kg') corresponds to '207 lb' after converting back to imperial -- expecting '95 kg' in order to match first value of '210 lb' (parsed from '210 lb')",
        ),
      ),
    );
  });

  test('parse list with conflicting values in same system', () {
    expect(
      () => Weight.parseList(['210 lb', '209 lb']),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message ==
                  "Conflicting weight information: '209 lb' (parsed from '209 lb') doesn't match first value '210 lb' (parsed from '210 lb')",
        ),
      ),
    );
  });
}
