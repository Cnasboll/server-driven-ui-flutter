import 'dart:convert';
import 'package:hero_common/models/appearance_model.dart';
import 'package:hero_common/models/biography_model.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:test/test.dart';
import 'package:hero_common/value_types/percentage.dart';
import 'package:hero_common/value_types/value_type.dart';

void main() {
  test('Can amend batman himself after parsing', () async {
    final rawJson = '''
{
  "response": "success",
  "id": "70",
  "name": "Batman",
  "powerstats": {
    "intelligence": "100",
    "strength": "26",
    "speed": "27",
    "durability": "50",
    "power": "47",
    "combat": "100"
  },
  "biography": {
    "full-name": "Bruce Wayne",
    "alter-egos": "No alter egos found.",
    "aliases": ["Insider", "Matches Malone"],
    "place-of-birth": "Crest Hill, Bristol Township; Gotham County",
    "first-appearance": "Detective Comics #27",
    "publisher": "DC Comics",
    "alignment": "good"
  },
  "appearance": {
    "gender": "Male",
    "race": "Human",
    "height": ["6'2", "188 cm"],
    "weight": ["210 lb", "95 kg"],
    "eye-color": "blue",
    "hair-color": "black"
  },
  "work": {
    "occupation": "Businessman",
    "base": "Batcave, Stately Wayne Manor, Gotham City; Hall of Justice, Justice League Watchtower"
  },
  "connections": {
    "group-affiliation": "Batman Family, Batman Incorporated, Justice League, Outsiders, Wayne Enterprises, Club of Heroes, formerly White Lantern Corps, Sinestro Corps",
    "relatives": "Damian Wayne (son), Dick Grayson (adopted son), Tim Drake (adopted son), Jason Todd (adopted son), Cassandra Cain (adopted ward), Martha Wayne (mother, deceased)"
  },
  "image": {
    "url": "https://www.superherodb.com/pictures2/portraits/10/100/639.jpg"
  }
}
''';

    var decoded = json.decode(rawJson);
    final batman = await HeroModel.fromJsonAndIdAsync(
      decoded,
      "02ffbb60-762b-4552-8f41-be8aa86869c6",
    );

    var amedment = {
      "powerstats": {"intelligence": "96", "durability": "45"},
      "appearance": {
        "weight": ["220 lb", "100 kg"],
        "height": ["6'1", "186 cm"]
      },
      "biography": {
        "alter-egos": "Owlman",
        "aliases": ["Mystical"],
        "alignment": "reasonable",
      },
    };

    final fatman = await batman.amendWith(amedment);

    StringBuffer sb = StringBuffer();
    batman.diff(fatman, sb);
    expect(sb.toString(), '''Powerstats: Intelligence: 100 -> 96
Powerstats: Durability: 50 -> 45
Biography: Alter Egos: null -> Owlman
Biography: Aliases: [Insider, Matches Malone] -> [Mystical]
Biography: Alignment: good -> reasonable
Appearance: Height: 6'2" -> 6'1"
Appearance: Weight: 210 lb -> 220 lb
''');

    expect(fatman.id, "02ffbb60-762b-4552-8f41-be8aa86869c6");
    expect(fatman.externalId, "70");
    // auto-incremented 1->2
    expect(fatman.version, 2);
    expect(fatman.name, "Batman");

    var powerStats = fatman.powerStats;
    expect(powerStats.strength,  Percentage(26));
    expect(powerStats.speed,  Percentage(27));
    // 100->96, can happen after working too long with handling unit inconsistencies between metric and imperial
    expect(powerStats.intelligence, Percentage(96));
    expect(powerStats.durability, Percentage(45));
    expect(powerStats.power, Percentage(47));
    expect(powerStats.combat, Percentage(100));

    var biography = fatman.biography;
    expect(biography.fullName, "Bruce Wayne");
    // Special string literal in the API to indicate no alter egos exist -- treat as null
    expect(biography.alterEgos, "Owlman");
    expect(biography.aliases, ["Mystical"]);
    expect(
      biography.placeOfBirth,
      "Crest Hill, Bristol Township; Gotham County",
    );
    expect(biography.firstAppearance, "Detective Comics #27");
    expect(biography.publisher, "DC Comics");
    // good->reasonable, can happen with age as complex moral issues arise
    expect(biography.alignment, Alignment.reasonable);

    var appearance = fatman.appearance;
    expect(appearance.gender, Gender.male);
    expect(appearance.race, "Human");
    var height = appearance.height;
    // This parsing and verification of integrity between representations of Height and Weight is really the biggest part of this assignment for me.
    // Of course it is internally represented in metric but for purposes of formatting the system of units is tied to the value object
    // so the database mapping does store the height and weight in SI units but encode the original system of units that was read from the json as an enum
    // so that the UI can format it appropriately.
    expect(height.wholeFeetAndWholeInches, (6, 1));
    // 188->186 cm can happen with age and posture changes, but the final cm from 186 to 185 was lost to debilitating roundingitis from inches!
    expect(height.wholeCentimeters, 185);
    expect(height.systemOfUnits, SystemOfUnits.imperial);
    var weight = appearance.weight;
    // 95->100 kgs, can happen, been there, done that
    expect(weight.wholePounds, 220);
    // The api rounds the weight in kilos down so it handles 99.7903 kg as 99 kg instead of 100
    expect(weight.wholeKilograms, 99);
    expect(weight.systemOfUnits, SystemOfUnits.imperial);
    expect(appearance.eyeColor, "blue");
    expect(appearance.hairColor, "black");

    var work = fatman.work;
    expect(work.occupation, "Businessman");
    expect(
      work.base,
      "Batcave, Stately Wayne Manor, Gotham City; Hall of Justice, Justice League Watchtower",
    );
    var connections = fatman.connections;
    expect(
      connections.groupAffiliation,
      "Batman Family, Batman Incorporated, Justice League, Outsiders, Wayne Enterprises, Club of Heroes, formerly White Lantern Corps, Sinestro Corps",
    );
    expect(
      connections.relatives,
      "Damian Wayne (son), Dick Grayson (adopted son), Tim Drake (adopted son), Jason Todd (adopted son), Cassandra Cain (adopted ward), Martha Wayne (mother, deceased)",
    );
    var image = fatman.image;
    expect(
      image.url,
      "https://www.superherodb.com/pictures2/portraits/10/100/639.jpg",
    );
  });
}
