import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:hero_common/hero_common.dart';
import 'package:v04/persistence/sqlite3_database_adapter.dart';
import 'package:test/test.dart';

final DateTime deadline = DateTime.parse("2025-10-28T18:00:00.000000Z");

Future<void> main() async {
  test('DB test', () async {
    var path = "v04_test.db";
    var file = File(path);

    if (await file.exists()) {
      await file.delete();
    }

    final constantsSet = Runtime.prepareConstantsSet();
    HeroShqlAdapter.registerHeroSchema(constantsSet);
    final runtime = Runtime.prepareRuntime(constantsSet);

    // First create a db instance, clean it, add some heroes, then shutdown
    var heroDataManager = HeroDataManager(
      await HeroRepository.create(path, Sqlite3Driver()),
      runtime: runtime,
      constantsSet: constantsSet,
    );
    heroDataManager.clear();

    var parsingContext = HeroParsingContext(
      "02ffbb60-762b-4552-8f41-be8aa86869c6",
      "70",
      "Batman",
      false,
    );

    heroDataManager.persist(
      HeroModel(
        id: parsingContext.id,
        version: 1,
        timestamp: deadline,
        locked: false,
        externalId: parsingContext.externalId,
        name: parsingContext.name,
        powerStats: PowerStatsModel(
          intelligence: Percentage(50),
          strength: Percentage(26),
          speed: Percentage(27),
          durability: Percentage(50),
          power: Percentage(47),
          combat: Percentage(100),
        ),
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
          height: await Height.parseList([
            "6'2",
            "188 cm",
          ], parsingContext: parsingContext),
          weight: await Weight.parseList([
            "210 lb",
            "95 kg",
          ], parsingContext: parsingContext),
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
      ),
    );

    parsingContext = HeroParsingContext(
      "008b98a5-3ce6-4448-99f4-d4ce296fcdfc",
      "69",
      "Robin",
      false,
    );
    heroDataManager.persist(
      HeroModel(
        id: parsingContext.id,
        version: 1,
        timestamp: deadline,
        locked: false,
        externalId: parsingContext.externalId,
        name: parsingContext.name,
        powerStats: PowerStatsModel(
          intelligence: Percentage(51),
          strength: Percentage(23),
          speed: Percentage(28),
          durability: Percentage(57),
          power: Percentage(30),
          combat: Percentage(99),
        ),
        biography: BiographyModel(
          fullName: "Dick Grayson",
          alterEgos: "Nightwing",
          aliases: ["Robin", "Nightwing"],
          placeOfBirth: "Gotham City",
          firstAppearance: "Detective Comics #38",
          publisher: "DC Comics",
          alignment: Alignment.reasonable,
        ),
        appearance: AppearanceModel(
          gender: Gender.unknown,
          race: "Human",
          height: await Height.parseList([
            "5'10",
            "178 cm",
          ], parsingContext: parsingContext),
          weight: await Weight.parseList([
            "159 lb",
            "72 kg",
          ], parsingContext: parsingContext),
          eyeColor: 'blue',
          hairColor: 'black',
        ),
        work: WorkModel(occupation: "Hero", base: "Gotham City"),
        connections: ConnectionsModel(
          groupAffiliation: "Teen Titans, Batman Family",
          relatives: "Bruce Wayne (guardian), Alfred Pennyworth (butler)",
        ),
        image: ImageModel(
          url: "https://www.superherodb.com/pictures2/portraits/10/100/639.jpg",
        ),
      ),
    );
    await heroDataManager.dispose();

    // Now create a new db instance, read the snapshot, and verify
    heroDataManager = HeroDataManager(
      await HeroRepository.create(path, Sqlite3Driver()),
      runtime: runtime,
      constantsSet: constantsSet,
    );
    var snapshot = heroDataManager.heroes;
    expect(2, snapshot.length);
    var batman = (await heroDataManager.query("batman"))[0];
    expect(batman.id, "02ffbb60-762b-4552-8f41-be8aa86869c6");
    expect(batman.version, 1);
    expect(batman.timestamp, deadline);
    expect(batman.externalId, "70");
    expect(batman.name, "Batman");
    expect(batman.powerStats.strength, Percentage(26));
    expect(batman.appearance.gender, Gender.male);
    expect(batman.biography.alignment, Alignment.mostlyGood);
    expect(batman.appearance.race, "Human");

    var robin = (await heroDataManager.query("robin"))[0];
    expect(robin.id, "008b98a5-3ce6-4448-99f4-d4ce296fcdfc");
    expect(robin.version, 1);
    expect(robin.timestamp, deadline);
    expect(robin.externalId, "69");
    expect(robin.name, "Robin");
    expect(robin.powerStats.strength, Percentage(23));
    expect(robin.appearance.gender, Gender.unknown);
    expect(robin.biography.alignment, Alignment.reasonable);
    expect(robin.appearance.race, "Human");

    // Modify Batman's strength and aligment
    batman = batman.copyWith(
      powerStats: batman.powerStats.copyWith(strength: Percentage(13)),
      biography: batman.biography.copyWith(alignment: Alignment.good),
    );
    heroDataManager.persist(batman);

    // Add Alfred, assign a id
    parsingContext = HeroParsingContext(Uuid().v4(), "3", "Alfred", false);
    var alfred = HeroModel(
      id: parsingContext.id,
      version: 1,
      timestamp: deadline,
      locked: false,
      externalId: parsingContext.externalId,
      name: parsingContext.name,
      powerStats: PowerStatsModel(strength: Percentage(9)),
      biography: BiographyModel(
        alignment: Alignment.good,
        fullName: "Alfred Pennyworth",
      ),
      appearance: AppearanceModel(
        gender: Gender.wontSay,
        race: "Human",
        height: await Height.parseList([
          "5'9",
          "175 cm",
        ], parsingContext: parsingContext),
        weight: await Weight.parseList([
          "155 lb",
          "70 kg",
        ], parsingContext: parsingContext),
      ),
      work: WorkModel(occupation: "Butler", base: "Wayne Manor"),
      connections: ConnectionsModel(
        groupAffiliation: "Wayne Manor",
        relatives: "Bruce Wayne (employer)",
      ),
      image: ImageModel(
        url: "https://www.superherodb.com/pictures2/portraits/10/100/639.jpg",
      ),
    );
    heroDataManager.persist(alfred);

    //delete Robin
    heroDataManager.delete(robin);

    // then shutdown
    await heroDataManager.dispose();

    heroDataManager = HeroDataManager(
      await HeroRepository.create(path, Sqlite3Driver()),
      runtime: runtime,
      constantsSet: constantsSet,
    );
    snapshot = heroDataManager.heroes;
    expect(2, snapshot.length);
    batman = heroDataManager.getById(batman.id)!;
    expect(batman.version, 2);
    expect(batman.name, "Batman");
    expect(batman.powerStats.strength, Percentage(13));

    alfred = heroDataManager.getById(alfred.id)!;
    expect(alfred.version, 1);
    expect(alfred.name, "Alfred");
    expect(alfred.powerStats.strength, Percentage(9));
    await heroDataManager.dispose();

    file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  });
}
