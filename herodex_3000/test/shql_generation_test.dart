import 'package:flutter_test/flutter_test.dart';
import 'package:hero_common/models/hero_shql_adapter.dart';
import 'package:shql/parser/constants_set.dart';

import 'package:herodex_3000/core/hero_schema.dart';

void main() {
  test('generate SHQL™ schema script', () {
    // HeroShqlAdapter must register enums first so enumLabelsFor() works.
    final cs = ConstantsSet();
    HeroShqlAdapter.registerHeroSchema(cs);

    final script = HeroSchema.generateSchemaScript();
    expect(script, '''
-- ============================================
-- Auto-generated HeroSchema (from Field tree)
-- ============================================

-- NVL accessor functions
POWERSTATS(hero, f, default) := NVL(NVL(NVL(hero, h => h.POWERSTATS, null), f, null), v => v, default);
BIOGRAPHY(hero, f, default) := NVL(NVL(NVL(hero, h => h.BIOGRAPHY, null), f, null), v => v, default);
APPEARANCE(hero, f, default) := NVL(NVL(NVL(hero, h => h.APPEARANCE, null), f, null), v => v, default);
WORK(hero, f, default) := NVL(NVL(NVL(hero, h => h.WORK, null), f, null), v => v, default);
CONNECTIONS(hero, f, default) := NVL(NVL(NVL(hero, h => h.CONNECTIONS, null), f, null), v => v, default);
IMAGE(hero, f, default) := NVL(NVL(NVL(hero, h => h.IMAGE, null), f, null), v => v, default);

-- Value type helpers
HEIGHT_M(hero, default) := BEGIN v := NVL(APPEARANCE(hero, a => a.HEIGHT, null), x => x.M, null); RETURN IF v = null OR v <= 0 THEN default ELSE v; END;
WEIGHT_KG(hero, default) := BEGIN v := NVL(APPEARANCE(hero, a => a.WEIGHT, null), x => x.KG, null); RETURN IF v = null OR v <= 0 THEN default ELSE v; END;

-- Detail fields metadata
_detail_fields := [
    OBJECT{section: 'Power Stats', label: 'Intelligence', accessor: (hero) => POWERSTATS(hero, x => x.INTELLIGENCE, 0), display_type: 'stat', color: '0xFF2196F3'},
    OBJECT{section: 'Power Stats', label: 'Strength', accessor: (hero) => POWERSTATS(hero, x => x.STRENGTH, 0), display_type: 'stat', color: '0xFFF44336'},
    OBJECT{section: 'Power Stats', label: 'Speed', accessor: (hero) => POWERSTATS(hero, x => x.SPEED, 0), display_type: 'stat', color: '0xFFFF9800'},
    OBJECT{section: 'Power Stats', label: 'Durability', accessor: (hero) => POWERSTATS(hero, x => x.DURABILITY, 0), display_type: 'stat', color: '0xFF4CAF50'},
    OBJECT{section: 'Power Stats', label: 'Power', accessor: (hero) => POWERSTATS(hero, x => x.POWER, 0), display_type: 'stat', color: '0xFF9C27B0'},
    OBJECT{section: 'Power Stats', label: 'Combat', accessor: (hero) => POWERSTATS(hero, x => x.COMBAT, 0), display_type: 'stat', color: '0xFF795548'},
    OBJECT{section: 'Biography', label: 'Full Name', accessor: (hero) => BIOGRAPHY(hero, x => x.FULL_NAME, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Biography', label: 'Alter Egos', accessor: (hero) => BIOGRAPHY(hero, x => x.ALTER_EGOS, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Biography', label: 'Aliases', accessor: (hero) => BIOGRAPHY(hero, x => x.ALIASES, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Biography', label: 'Place of Birth', accessor: (hero) => BIOGRAPHY(hero, x => x.PLACE_OF_BIRTH, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Biography', label: 'First Appearance', accessor: (hero) => BIOGRAPHY(hero, x => x.FIRST_APPEARANCE, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Biography', label: 'Publisher', accessor: (hero) => BIOGRAPHY(hero, x => x.PUBLISHER, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Biography', label: 'Alignment', accessor: (hero) => BIOGRAPHY(hero, x => x.ALIGNMENT, 0), display_type: 'enum_label', enum_labels: _ALIGNMENT_LABELS},
    OBJECT{section: 'Appearance', label: 'Gender', accessor: (hero) => APPEARANCE(hero, x => x.GENDER, 0), display_type: 'enum_label', enum_labels: _GENDER_LABELS},
    OBJECT{section: 'Appearance', label: 'Race', accessor: (hero) => APPEARANCE(hero, x => x.RACE, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Appearance', label: 'Height', accessor: (hero) => HEIGHT_M(hero, 0), display_type: 'measurement', unit: 'm'},
    OBJECT{section: 'Appearance', label: 'Weight', accessor: (hero) => WEIGHT_KG(hero, 0), display_type: 'measurement', unit: 'kg'},
    OBJECT{section: 'Appearance', label: 'Eye Colour', accessor: (hero) => APPEARANCE(hero, x => x.EYE_COLOUR, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Appearance', label: 'Hair Colour', accessor: (hero) => APPEARANCE(hero, x => x.HAIR_COLOUR, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Work', label: 'Occupation', accessor: (hero) => WORK(hero, x => x.OCCUPATION, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Work', label: 'Base', accessor: (hero) => WORK(hero, x => x.BASE, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Connections', label: 'Group Affiliation', accessor: (hero) => CONNECTIONS(hero, x => x.GROUP_AFFILIATION, 'Unknown'), display_type: 'text'},
    OBJECT{section: 'Connections', label: 'Relatives', accessor: (hero) => CONNECTIONS(hero, x => x.RELATIVES, 'Unknown'), display_type: 'text'}
];

-- Summary fields metadata (for HeroCard)
_summary_fields := [
    OBJECT{prop_name: 'name', accessor: (hero) => hero.NAME, is_stat: FALSE},
    OBJECT{prop_name: 'intelligence', accessor: (hero) => POWERSTATS(hero, x => x.INTELLIGENCE, 0), is_stat: TRUE, label: 'INT', color: '0xFF2196F3', bg_color: '0x1A2196F3'},
    OBJECT{prop_name: 'strength', accessor: (hero) => POWERSTATS(hero, x => x.STRENGTH, 0), is_stat: TRUE, label: 'STR', color: '0xFFF44336', bg_color: '0x1AF44336'},
    OBJECT{prop_name: 'speed', accessor: (hero) => POWERSTATS(hero, x => x.SPEED, 0), is_stat: TRUE, label: 'SPE', color: '0xFFFF9800', bg_color: '0x1AFF9800'},
    OBJECT{prop_name: 'durability', accessor: (hero) => POWERSTATS(hero, x => x.DURABILITY, 0), is_stat: TRUE, label: 'DUR', color: '0xFF4CAF50', bg_color: '0x1A4CAF50'},
    OBJECT{prop_name: 'power', accessor: (hero) => POWERSTATS(hero, x => x.POWER, 0), is_stat: TRUE, label: 'POW', color: '0xFF9C27B0', bg_color: '0x1A9C27B0'},
    OBJECT{prop_name: 'combat', accessor: (hero) => POWERSTATS(hero, x => x.COMBAT, 0), is_stat: TRUE, label: 'COM', color: '0xFF795548', bg_color: '0x1A795548'},
    OBJECT{prop_name: 'fullName', accessor: (hero) => BIOGRAPHY(hero, x => x.FULL_NAME, ''), is_stat: FALSE},
    OBJECT{prop_name: 'publisher', accessor: (hero) => BIOGRAPHY(hero, x => x.PUBLISHER, ''), is_stat: FALSE},
    OBJECT{prop_name: 'alignment', accessor: (hero) => BIOGRAPHY(hero, x => x.ALIGNMENT, 0), is_stat: FALSE},
    OBJECT{prop_name: 'race', accessor: (hero) => APPEARANCE(hero, x => x.RACE, ''), is_stat: FALSE},
    OBJECT{prop_name: 'url', accessor: (hero) => IMAGE(hero, x => x.URL, ''), is_stat: FALSE},
    OBJECT{prop_name: 'totalPower', accessor: (hero) => POWERSTATS(hero, p => p.INTELLIGENCE, 0) + POWERSTATS(hero, p => p.STRENGTH, 0) + POWERSTATS(hero, p => p.SPEED, 0) + POWERSTATS(hero, p => p.DURABILITY, 0) + POWERSTATS(hero, p => p.POWER, 0) + POWERSTATS(hero, p => p.COMBAT, 0), is_stat: FALSE}
];
''');
  });
}
