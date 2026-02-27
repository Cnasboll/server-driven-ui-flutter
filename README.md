# server-driven-ui-flutter

An abstraction layer on top of Flutter where applications are written in **YAML** and **SHQL™**, not Dart.

YAML defines what the UI *looks like* — structure, layout, styling, composition. SHQL™ defines what the UI *does* — state, logic, data flow, navigation. Dart and Flutter serve as the runtime substrate: they render widgets, talk to SQLite, call Firebase, and handle platform I/O. You don't program *in* Flutter — Flutter is the engine underneath.

The flagship app, **HeroDex 3000**, has zero Dart widget code. Every screen, every dialog, every reusable component is a YAML template. All business logic — filtering, searching, statistics, dynamic widget tree generation — is SHQL™. Dart appears only in the framework interpreter and at genuine third-party library boundaries (e.g. `CachedNetworkImage`, `FlutterMap`).

## The two layers

### YAML — declarative UI

YAML files define screens and reusable widget templates. The framework resolves `shql:` expressions in the YAML at runtime, and a `WidgetRegistry` maps type names to Flutter widgets. Templates are composable: a screen references a widget template by type name and passes props via `"prop:name"` placeholders, substituted at build time. Callback props (`on*` keys) are automatically treated as SHQL™ expressions.

### SHQL™ — imperative logic

SHQL™ (Small, Handy, Quintessential Language™) is a general-purpose, Turing-complete scripting language with an async Algol-family VM. It is the *only* language application authors write logic in.

Features:
- Variables, first-class functions, lambdas, closures
- Loops (`FOR`, `WHILE`, `REPEAT`), conditionals (`IF`/`THEN`/`ELSE`)
- Object literals with dot-notation access (`hero.POWERSTATS.STRENGTH`)
- Lists, string operations, regular expression matching
- Mathematical functions inherited from the calculator project
- Swedish operator aliases (`OCH`, `ELLER`, `INTE`, `FINNS_I`)
- State persistence (`SAVE_STATE`, `LOAD_STATE`)
- Navigation (`GO_TO`, `GO_BACK`, `PUSH_ROUTE`)
- Dynamic widget tree generation — SHQL™ functions return complete widget tree maps that the framework renders

The language is tokenized, parsed into an AST, and executed by an async runtime with interned identifiers (`ConstantsSet`). SHQL™ needs native Dart callbacks only for platform operations — displaying a dialog, writing to a file, calling the network. These are registered as functions on the runtime, then wrapped in SHQL™ so the application layer never touches Dart.

### Where does Dart fit?

Dart is the *interpreter*, not the application. It exists in three places:

1. **The SHQL™ engine** (`shql/`) — tokenizer, parser, runtime
2. **The SDUI framework** (`server_driven_ui/`) — YAML resolver, widget registry, Observer
3. **Platform boundaries** — SQLite adapters, Firebase auth, network fetch, geolocation

Everything above this line — UI structure, business logic, state management, navigation — is YAML + SHQL™.

## Mono-repo layout

```
shql/                 — SHQL™ language engine
  lib/                  Parser, tokenizer, execution nodes, runtime
  assets/stdlib.shql    Standard library (SET, LOAD_STATE, SAVE_STATE, etc.)

server_driven_ui/     — SDUI framework (Flutter package)
  lib/yaml_ui/          YamlUiEngine, WidgetRegistry, ShqlBindings, Observer
                        Renders YAML + SHQL™ into Flutter widget trees

hero_common/          — Shared Dart package (no platform dependencies)
  lib/                  Models, fields, persistence, services, value types
                        DatabaseDriver/DatabaseAdapter strategy pattern

herodex_3000/         — Flutter mobile app (SDUI showcase)
  assets/screens/       7 YAML screen definitions
  assets/widgets/       17 YAML widget templates (login, cards, dialogs, nav, etc.)
  assets/shql/          SHQL™ business logic + dynamic widget tree generation
  lib/                  App shell, auth, services, 4 thin Dart widget factories
                        for third-party libraries (CachedNetworkImage, FlutterMap)

v04/                  — Console app (same hero_common backend, terminal UI)
  lib/                  Terminal menus, effects, SQLite persistence
                        Uses SHQL™ for search predicates and hero filtering

awesome_calculator/   — Calculator app (SHQL™ shell without YAML/SDUI)
  lib/                  Terminal-style UI with SHQL™ interpreter
                        Supports PLOT(), LOAD/SAVE programs, math functions
                        Demonstrates SHQL™ as a standalone scripting language
```

## Packages

| Package | Description |
|---|---|
| **shql** | The SHQL™ engine: tokenizer, parser, AST, async runtime. No Flutter dependency. |
| **server_driven_ui** | SDUI framework: `YamlUiEngine` resolves SHQL™ in YAML, `WidgetRegistry` maps types to widgets, `ShqlBindings` bridges SHQL™ variables to Flutter state, `Observer` widget rebuilds on variable changes. |
| **hero_common** | Shared models (`HeroModel`, `PowerStatsModel`, etc.), `Field<T,V>` metadata system, `HeroRepository` (SQL, caching, job queue), `ConflictResolver` for height/weight unit conflicts, value types. No platform dependencies — used by both herodex_3000 and v04. |
| **herodex_3000** | Flutter app showcasing the full SDUI stack. All UI in YAML + SHQL™. Only 4 Dart widget factories for third-party library boundaries (`CachedImage`, `FlutterMap`, `TileLayer`, `MarkerLayer`). Firebase Auth, Firestore sync, location services, connectivity monitoring. |
| **v04** | Console (terminal) app using the same `hero_common` backend. SHQL™ predicates for searching/filtering heroes. Menu-driven CRUD, online search, reconciliation, amendments. |
| **awesome_calculator** | Standalone SHQL™ shell — no YAML, no SDUI. Calculator with PLOT(), program LOAD/SAVE, math functions. Demonstrates that SHQL™ is a general-purpose language independent of the UI framework. |

## Quick start

```bash
git clone <repo-url>
cd server-driven-ui-flutter

# Dependencies (order matters — hero_common and shql first)
cd hero_common && dart pub get && cd ..
cd shql && dart pub get && cd ..
cd server_driven_ui && flutter pub get && cd ..
cd herodex_3000 && flutter pub get

# Run the Flutter app
flutter run

# Or run the console app
cd ../v04 && dart run

# Or run the calculator
cd ../awesome_calculator && flutter run
```

## Testing

```bash
# Shared models, predicates, SHQL™ engine (245+ tests)
cd hero_common && dart test

# Console app (SQL generation, hero service, JSON parsing)
cd v04 && dart test

# Flutter app (DB, connectivity, hero cards, splash)
cd herodex_3000 && flutter test
```

## License

Course project for HFL25-2 (Flutter), 2026.
