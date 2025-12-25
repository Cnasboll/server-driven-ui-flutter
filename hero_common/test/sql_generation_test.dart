import 'package:test/test.dart';
import 'package:hero_common/models/hero_model.dart';

void main() {
  test('generate SQLite column names', () {
    final names = HeroModel.generateSqliteColumnNameList('      ');
    expect(names, '''
      id,
      version,
      timestamp,
      locked,
      external_id,
      name,
      intelligence,
      strength,
      speed,
      durability,
      power,
      combat,
      full_name,
      alter_egos,
      aliases,
      place_of_birth,
      first_appearance,
      publisher,
      alignment,
      gender,
      race,
      height_m,
      height_system_of_units,
      weight_kg,
      weight_system_of_units,
      eye_colour,
      hair_colour,
      occupation,
      base,
      group_affiliation,
      relatives,
      image_url
''');
  });

  test('generate SQLite column declarations', () {
    final declarations = HeroModel.generateSqliteColumnDeclarations('  ');
    expect(declarations, '''
  id TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  timestamp TEXT NOT NULL,
  locked BOOLEAN NOT NULL,
  external_id TEXT NOT NULL,
  name TEXT NOT NULL,
  intelligence INTEGER NULL,
  strength INTEGER NULL,
  speed INTEGER NULL,
  durability INTEGER NULL,
  power INTEGER NULL,
  combat INTEGER NULL,
  full_name TEXT NULL,
  alter_egos TEXT NULL,
  aliases TEXT NULL,
  place_of_birth TEXT NULL,
  first_appearance TEXT NULL,
  publisher TEXT NULL,
  alignment TEXT NOT NULL,
  gender TEXT NOT NULL,
  race TEXT NULL,
  height_m REAL NOT NULL,
  height_system_of_units TEXT NOT NULL,
  weight_kg REAL NOT NULL,
  weight_system_of_units TEXT NOT NULL,
  eye_colour TEXT NULL,
  hair_colour TEXT NULL,
  occupation TEXT NULL,
  base TEXT NULL,
  group_affiliation TEXT NULL,
  relatives TEXT NULL,
  image_url TEXT NULL
''');
  });

  test('generate SQLite update clause', () {
    final update = HeroModel.generateSqliteUpdateClause('    ');
    expect(update, '''version=excluded.version,
    timestamp=excluded.timestamp,
    locked=excluded.locked,
    name=excluded.name,
    intelligence=excluded.intelligence,
    strength=excluded.strength,
    speed=excluded.speed,
    durability=excluded.durability,
    power=excluded.power,
    combat=excluded.combat,
    full_name=excluded.full_name,
    alter_egos=excluded.alter_egos,
    aliases=excluded.aliases,
    place_of_birth=excluded.place_of_birth,
    first_appearance=excluded.first_appearance,
    publisher=excluded.publisher,
    alignment=excluded.alignment,
    gender=excluded.gender,
    race=excluded.race,
    height_m=excluded.height_m,
    height_system_of_units=excluded.height_system_of_units,
    weight_kg=excluded.weight_kg,
    weight_system_of_units=excluded.weight_system_of_units,
    eye_colour=excluded.eye_colour,
    hair_colour=excluded.hair_colour,
    occupation=excluded.occupation,
    base=excluded.base,
    group_affiliation=excluded.group_affiliation,
    relatives=excluded.relatives,
    image_url=excluded.image_url
''');
  });

    test('generate SQLite insert column placeholders', () {
    final placeholders = HeroModel.generateSQLiteInsertColumnPlaceholders();
    expect(placeholders, '?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?');
  });
}
