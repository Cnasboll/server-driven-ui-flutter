import 'package:hero_common/models/appearance_model.dart';
import 'package:hero_common/models/biography_model.dart';
import 'package:hero_common/models/connections_model.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/image_model.dart';
import 'package:hero_common/models/power_stats_model.dart';
import 'package:hero_common/models/work_model.dart';
import 'dart:io';

import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:hero_common/predicates/hero_predicate.dart';
import 'package:hero_common/value_types/height.dart';
import 'package:hero_common/value_types/percentage.dart';
import 'package:hero_common/value_types/weight.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart' show Runtime;
import 'package:shql/parser/constants_set.dart';
import 'package:test/test.dart';

final DateTime deadline = DateTime.parse("2025-10-28T18:00:00.000000Z");

Future<void> main() async {
  late HeroModel batman;
  late Runtime runtime;
  late ConstantsSet constantsSet;

  setUp(() async {
    constantsSet = Runtime.prepareConstantsSet();
    HeroShqlAdapter.registerHeroSchema(constantsSet);
    runtime = Runtime.prepareRuntime(constantsSet);

    final stdlibCode = await File('../shql/assets/stdlib.shql').readAsString();
    await Engine.execute(stdlibCode, runtime: runtime, constantsSet: constantsSet);
    batman = HeroModel(
      id: "02ffbb60-762b-4552-8f41-be8aa86869c6",
      version: 1,
      timestamp: deadline,
      locked: false,
      externalId: "70",
      name: "Batman",
      powerStats: PowerStatsModel(intelligence: Percentage(5)),
      biography: BiographyModel(
        fullName: "Bruce Wayne",
        alterEgos: "No alter egos found.",
        aliases: ["Insider", "Matches Malone"],
        placeOfBirth: "Crest Hill, Bristol Township; Gotham County",
        firstAppearance: "Detective Comics #27",
        publisher: "DC Comics",
        alignment: Alignment.mostlyGood,
      ),
      appearance: AppearanceModel(
        gender: Gender.male,
        race: "Human",
        height: await Height.parseList(["6'2", "188 cm"]),
        weight: await Weight.parseList(["209 lb", "95 kg"]),
        eyeColor: 'blue',
        hairColor: 'black',
      ),
      work: WorkModel(
        occupation: "CEO of Wayne Enterprises",
        base: "Gotham City",
      ),
      connections: ConnectionsModel(
        groupAffiliation:
            "Batman Family, Batman Incorporated, Justice League, Outsiders, Wayne Enterprises, Club of Heroes, formerly White Lantern Corps, Sinestro Corps",
        relatives:
            "Damian Wayne (son), Dick Grayson (adopted son), Tim Drake (adopted son), Jason Todd (adopted son), Cassandra Cain (adopted ward), Martha Wayne (mother, deceased)",
      ),
      image: ImageModel(
        url: "https://www.superherodb.com/pictures2/portraits/10/100/639.jpg",
      ),
    );
  });

  test('Can evaluate name matching predicate', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'name ~ "Batman"');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can evaluate name equality predicate', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'name = "Batman"');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can evaluate name in list predicate', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'name in ["Batman", "Robin"]');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can evaluate lowercase name in list predicate', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'lowercase(name) in ["batman", "robin"]');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can evaluate biography.alignment = bad (should be false)', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'biography.alignment = bad');
    expect(await predicate.evaluate(batman), false);
  });

  test('Can evaluate biography.alignment > good (should be false)', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'biography.alignment > good');
    expect(await predicate.evaluate(batman), false);
  });

  test('Can evaluate biography.alignment = good (should be false)', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'biography.alignment = good');
    expect(await predicate.evaluate(batman), false);
  });

  test('Can evaluate BMI calculation', () async {
    // Batman: 209 lb = 94.8 kg, height 6'2" = 1.8796 m
    // BMI = 94.8 / (1.8796)^2 = ~26.8
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,
      'appearance.weight.kg / pow(appearance.height.m, 2) >= 25',
    );
    expect(await predicate.evaluate(batman), true);
  });

  test('Can evaluate work.base contains cave (should be false)', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'work.base ~ "cave"');
    expect(await predicate.evaluate(batman), false);
  });

  test('Can evaluate cave in work.base (should be false)', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'"cave" in work.base');
    expect(await predicate.evaluate(batman), false);
  });

  test('Can access powerstats.intelligence', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'powerstats.intelligence = 5');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can access biography.full_name', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'biography.full_name = "Bruce Wayne"');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can access biography.publisher', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'biography.publisher = "DC Comics"');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can access appearance.gender', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'appearance.gender = male');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can access appearance.race', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'appearance.race = "Human"');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can access work.occupation', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'work.occupation ~ "Wayne"');
    expect(await predicate.evaluate(batman), true);
  });

  test('Can access image.url', () async {
    var predicate = HeroPredicate(runtime: runtime, constantsSet: constantsSet,'image.url ~ "superherodb"');
    expect(await predicate.evaluate(batman), true);
  });
}
