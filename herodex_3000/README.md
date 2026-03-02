# HeroDex 3000

A superhero tracking app written entirely in **YAML** and **SHQL™** — not Dart.

Every screen, every dialog, every reusable widget is a YAML template. All business logic — filtering, searching, statistics, dynamic widget tree generation — is SHQL™. Flutter is the rendering engine underneath, but the application itself is written in a language layer above it. Dart appears only in the framework interpreter (`server_driven_ui/`, `shql/`) and at the boundary with third-party native libraries (`CachedNetworkImage`, `FlutterMap`).

## Architecture

### YAML + SHQL™

The UI is defined in YAML — both full screens and reusable widget templates. Business logic is defined in SHQL™ scripts. At runtime the `YamlUiEngine` resolves `shql:` expressions embedded in the YAML, and the `WidgetRegistry` maps type names to Flutter widgets. Widget templates are composable: a screen YAML references a template by type name and passes props that are substituted at build time. This means the UI can be updated without recompiling the app.

**Screens** (`assets/screens/`):
```
home.yaml        -> Home dashboard (battle map, hero cards)
online.yaml      -> Online hero search
heroes.yaml      -> Saved heroes database
settings.yaml    -> Settings & preferences
onboarding.yaml  -> First-run setup
hero_detail.yaml -> Hero detail view
hero_edit.yaml   -> Hero amendment editor
```

**Widget templates** (`assets/widgets/`):
```
login_screen.yaml      -> Login/register screen (pre-auth, static registry)
bottom_nav.yaml        -> Bottom navigation bar (shared across 5 screens)
hero_card_body.yaml    -> Card with border, InkWell, and column children
dismissible_card.yaml  -> Swipe-to-delete wrapper
hero_placeholder.yaml  -> Placeholder for missing hero images
stat_chip.yaml         -> Stat label + value chip
power_bar.yaml         -> Animated power stat bar
badge_row.yaml         -> Alignment badge row
overlay_action_button.yaml -> Positioned icon button overlay
consent_toggle.yaml    -> Icon + switch consent list tile
section_header.yaml    -> Blue section header text
info_card.yaml         -> Informational card with icon
api_field.yaml         -> Label + Observer-bound text field
detail_app_bar.yaml    -> AppBar with back button + Orbitron title
conflict_dialog.yaml   -> Height/weight conflict resolver dialog
yes_no_dialog.yaml     -> Yes/No confirmation dialog
reconcile_dialog.yaml  -> Hero reconciliation review dialog
prompt_dialog.yaml     -> Text input prompt dialog
```

SHQL™ also generates complete widget trees dynamically at runtime (e.g. `_MAKE_HERO_CARD_TREE` builds the full hero card including image, badge, overlays, stats; `GENERATE_BATTLE_MAP()` builds the FlutterMap with tile and marker layers).

### SHQL™ (Small, Handy, Quintessential Language™)

SHQL™ is a general-purpose, Turing-complete scripting language — the *only* language application logic is written in. Variables, functions, loops, conditionals, object literals with dot-notation access, lambdas, closures: everything you need to drive a full application without writing Dart.

SHQL™ needs native Dart callbacks only for platform operations (displaying a dialog, writing to a file, geolocation). Network requests are handled by built-in HTTP functions — `FETCH(url)` for GET, `POST(url, body)` and `PATCH(url, body)` for mutations. Firebase Auth sign-in/sign-up is pure SHQL™ (`auth.shql` POSTs to the Identity Toolkit REST API). Firestore preference sync is pure SHQL™ (`firestore.shql` PATCHes the Firestore REST API). Weather fetches live data from Open-Meteo entirely in SHQL™. No Dart service classes for any of these — only the HTTP client boundary exists in Dart.

It runs inside a `Runtime` with a `ConstantsSet` (interned identifiers).

- **`shql/`** — The language engine: parser, tokenizer, execution nodes, runtime
- **`assets/shql/`** — 12 cohesive SHQL™ scripts, each owning one concern: `auth` (Firebase Auth), `navigation` (route stack), `firestore` (Firestore sync), `preferences` (theme/onboarding/API config), `statistics` (running totals), `filters` (predicates & CRUD), `heroes` (collection state), `hero_detail` (detail view), `hero_cards` (card generation), `search` (API search), `hero_edit` (edit form), `world` (weather/map/war status)
- **`shql/assets/stdlib.shql`** — Standard library (SET, LOAD_STATE, SAVE_STATE, etc.)

Key SHQL™ patterns:
- `shql: _variable` — Bind a widget prop to a reactive variable
- `shql: FUNCTION(args)` — Call an SHQL™ function (e.g. `SEARCH_HEROES(query)`)
- `Observer` widget — Subscribes to SHQL™ variables and rebuilds on change
- `boundValues` — Pass Dart values to SHQL™ without string escaping
- Dynamic widget trees — SHQL™ functions return complete widget tree maps (e.g. `_MAKE_HERO_CARD_TREE` returns a `DismissibleCard > HeroCardBody > [CachedImage, StatChips, ...]` tree; `GENERATE_BATTLE_MAP()` returns a `FlutterMap > [TileLayer, MarkerLayer]` tree)
- `FETCH(url)` — Built-in HTTP GET + JSON parse (e.g. `REFRESH_WEATHER()` calls Open-Meteo API — zero Dart)
- `POST(url, body)` / `PATCH(url, body)` — HTTP mutations (e.g. `FIREBASE_SIGN_IN()` POSTs to Identity Toolkit, `FIRESTORE_SAVE()` PATCHes Firestore REST — zero Dart)
- `prop:` substitution — YAML widget templates use `"prop:name"` placeholders that are resolved to caller-provided values at build time; `on*` callback props are automatically treated as SHQL™ expressions

### Mono-repo structure

```
herodex_3000/     — Flutter mobile app (this package)
  assets/screens/ — YAML screen definitions (7 screens)
  assets/widgets/ — YAML widget templates (19 templates)
  assets/shql/    — SHQL™ business logic + widget tree generation
server_driven_ui/ — SDUI framework (YamlUiEngine, WidgetRegistry, ShqlBindings)
shql/             — SHQL™ language engine (parser, runtime, execution)
hero_common/      — Shared models, persistence, services (no platform dependencies)
v04/              — Console app (same backend, terminal UI)
```

### Database Layer (Strategy Pattern)

`hero_common` defines `DatabaseDriver` / `DatabaseAdapter` abstractions. Each app provides its own driver:

- **herodex_3000** uses `SqfliteDriver` (sqflite package for mobile)
- **v04** uses `Sqlite3Driver` (sqlite3 package for desktop)

`HeroRepository` contains all SQL logic and works with either driver.

### State Management

All application state lives in **SHQL™ runtime variables**. The `Observer` widget subscribes to variables and rebuilds when they change (via `SET()` / `PUBLISH()`). Persistence goes through `SAVE_STATE` / `LOAD_STATE` (SharedPreferences) and `Cloud.SAVE_PREF` / `Cloud.LOAD_ALL` (Firestore REST cloud sync — pure SHQL™).

#### Dart↔SHQL™ Boundary — Platform Primitives Only

SHQL™ drives **all** orchestration. Dart callbacks exist only for operations that require platform access (DB, dialogs, native APIs). No SHQL™→Dart→SHQL™ bounces — if SHQL™ calls Dart and needs to call SHQL™ afterwards, SHQL™ does both calls itself.

**Single source of truth:** `Heroes.heroes` (SHQL™ map) is the canonical hero collection. No Dart-side object cache exists. SHQL™ objects are created on the fly from `HeroModel` via `HeroShqlAdapter` when needed.

```
┌─────────────────────────────────────────────────────────────────────┐
│ SHQL™ Runtime (drives all orchestration)                           │
│                                                                     │
│  Heroes.RECONCILE_HEROES() ─── loop ──────────────────────────────┐│
│    │ __hero := heroes map (SHQL™ owns old objects)                 ││
│    ├── _RECONCILE_FETCH(id) ──→ Dart: fetch API + diff            ││
│    │   ←── {found, has_diff, diff_text}                           ││
│    ├── _RECONCILE_PROMPT(text) ──→ Dart: show dialog              ││
│    │   ←── 'save'|'skip'|'saveAll'|'cancel'                      ││
│    ├── RECONCILE_UPDATE(hero, new_obj, ...) ─ SHQL™ state update  ││
│    │   └── _PERSIST_HERO(model) ──→ Dart: persist to DB           ││
│    ├── RECONCILE_DELETE(hero, status, msg) ─ SHQL™ state cleanup  ││
│    │   └── _HERO_DELETE(id) ──→ Dart: DB delete                   ││
│    └── _FINISH_RECONCILE ──→ Dart: cleanup transient state        ││
│    └── FULL_REBUILD_AND_DISPLAY() ─── SHQL™ rebuild               ││
│  ─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  Heroes.DELETE_HERO(id)                                             │
│    │ __old := heroes[id]  (SHQL™ grabs old object)                 │
│    ├── ON_HERO_REMOVED(__old) ─── SHQL™ state cleanup              │
│    ├── Cards.REMOVE_CACHED_CARD(id) ─── SHQL™                     │
│    ├── _HERO_DELETE(id) ──→ Dart: DB delete                        │
│    ├── Filters.REBUILD_ALL_FILTERS() ─── SHQL™                    │
│    └── REBUILD_CARDS() ─── SHQL™                                   │
│                                                                     │
│  HeroEdit.SAVE_AMENDMENTS()                                        │
│    │ __old := Heroes.heroes[id]  (SHQL™ grabs old object)          │
│    ├── BUILD_AMENDMENT() ─── SHQL™ builds amendment map            │
│    ├── ON_HERO_REMOVED(__old) ─── SHQL™ (remove old state)         │
│    ├── Cards.REMOVE_CACHED_CARD(id) ─── SHQL™                     │
│    ├── _HERO_AMEND(id, amendment) ──→ Dart: apply + DB             │
│    │   ←── {new_obj, id}                                           │
│    ├── ON_HERO_ADDED(new_obj) ─── SHQL™ (add new state)            │
│    ├── Cards.CACHE_HERO_CARD(new_obj) ─── SHQL™ card cache         │
│    ├── Filters.REBUILD_ALL_FILTERS() ─── SHQL™                    │
│    ├── REBUILD_CARDS() ─── SHQL™                                   │
│    └── Heroes.FINISH_AMEND(id) ─── SHQL™ nav back                 │
│                                                                     │
│  Prefs.__SAVE(key, value)                                           │
│    ├── Cloud.SAVE_PREF(key, value) ─── SHQL™ Firestore sync       │
│    ├── PUBLISH('Prefs.' + key) ─── SHQL™ Observer notification     │
│    └── _ON_PREF_CHANGED(key, value) ──→ Dart: ThemeCubit/Firebase  │
└─────────────────────────────────────────────────────────────────────┘
```

**Dart callback registry** (registered in `app.dart`, called from SHQL™):

| Callback | Category | What it does |
|----------|----------|-------------|
| `_HERO_CLEAR` | DB | Clear all hero data |
| `_HERO_DELETE(id)` | DB | Delete hero, return `true` |
| `_HERO_AMEND(id, amendment)` | DB | Apply amendment, return `{new_obj, id}` |
| `_HERO_TOGGLE_LOCK(id)` | DB | Toggle lock, return `{locked}` |
| `_RECONCILE_FETCH(id)` | DB+Net | Fetch online data, diff, return result |
| `_PERSIST_HERO(model)` | DB | Persist opaque HeroModel, return SHQL™ Object |
| `_INIT_RECONCILE` | Net | Acquire HeroService |
| `_FINISH_RECONCILE` | Lifecycle | Cleanup transient reconcile state |
| `_SEARCH_HEROES(query)` | Net | Search API, return opaque HeroModel list |
| `_COMPILE_FILTERS` | Dart lib | Compile all filter predicates |
| `_COMPILE_QUERY(query)` | Dart lib | Compile single query to lambda |
| `_BUILD_EDIT_FIELDS(id)` | Dart lib | Build field descriptors from hero model |
| `_EVAL_PREDICATE(hero, pred, text)` | Dart lib | Eval compiled predicate with fallback |
| `MATCH(hero, text)` | Dart lib | Text-match hero model fields |
| `_SHOW_SNACKBAR(msg)` | UI | Show snackbar |
| `_PROMPT(prompt, default)` | UI | Show text input dialog |
| `_RECONCILE_PROMPT(text)` | UI | Show reconcile review dialog |
| `_REVIEW_HERO(hero, cur, total)` | UI | Show hero review dialog |
| `_SET_DARK_MODE(value)` | UI | Forward dark mode to ThemeCubit |
| `_SET_ANALYTICS(enabled)` | UI | Enable/disable Firebase Analytics |
| `_SET_CRASHLYTICS(enabled)` | UI | Enable/disable Firebase Crashlytics |
| `_GET_LOCATION(enabled)` | UI | Enable/disable GPS location |
| `_REFRESH_HERO_SERVICE(null)` | Net | Rebuild HeroService with new API credentials |
| `_SIGN_OUT` | Auth | Sign out + archive prefs |
| `_PUBLISH_SEARCH_RESULTS` | Search | Refresh search result display |

#### BLoC — ThemeCubit

The one place `flutter_bloc` appears is `ThemeCubit` — a 10-line Cubit that holds the current `ThemeMode`. It exists because the course requires demonstrating the BLoC pattern.

Dark mode state is owned by SHQL™ (`Prefs.is_dark_mode`), toggled by SHQL™ (`Prefs.TOGGLE_DARK_MODE()`), persisted by SHQL™ (`Prefs.__SAVE`), and the settings UI rebuilds via `PUBLISH`. `Prefs.__SAVE` calls `Prefs._ON_PREF_CHANGED(key, value)` — a SHQL™ function that dispatches to individual Dart callbacks based on the key:

```
_ON_PREF_CHANGED: (key, value) => BEGIN
    IF key = 'is_dark_mode' THEN _SET_DARK_MODE(value)              -- → Dart: ThemeCubit
    ELSE IF key = 'analytics_enabled' THEN _SET_ANALYTICS(value)    -- → Dart: Firebase
    ELSE IF key = 'crashlytics_enabled' THEN _SET_CRASHLYTICS(value)
    ELSE IF key = 'location_enabled' THEN _GET_LOCATION(value)      -- → Dart: GPS
    ELSE IF key = 'api_key' OR key = 'api_host' THEN _REFRESH_HERO_SERVICE(null);
END,
```

No Dart listeners — SHQL™ pushes preference changes to Dart, not the other way around.

| Concern | Owner |
|---------|-------|
| Preference state | SHQL™ (`Prefs.is_dark_mode`, etc.) |
| Persistence | SHQL™ (`Prefs.__SAVE` → `SAVE_STATE` + `Cloud.SAVE_PREF`) |
| Toggle logic | SHQL™ (`Prefs.TOGGLE_DARK_MODE()`) |
| Settings UI rebuild | SHQL™ `PUBLISH('Prefs.is_dark_mode')` |
| MaterialApp theme | `ThemeCubit` (via `_SET_DARK_MODE` Dart callback, course requirement) |

## Prerequisites

- Flutter SDK ^3.10.4
- A free API key from [superheroapi.com](https://superheroapi.com)

## Setup & Run

```bash
# Clone the repository
git clone <repo-url>
cd server-driven-ui-flutter

# Get dependencies for all packages
cd hero_common && dart pub get && cd ..
cd shql && dart pub get && cd ..
cd server_driven_ui && flutter pub get && cd ..
cd herodex_3000 && flutter pub get

# Run the app
flutter run
```

On first launch you will be asked to sign in or register (Firebase Auth). After authentication the onboarding screen lets you configure your API key and filter predicates.

You can also set the API key later in **Settings > API Configuration**.

## Features

### Basic Requirements

| Feature | Implementation |
|---|---|
| **Firebase Auth** | Pure SHQL™ sign-in/register gate (`auth.shql` POSTs to Identity Toolkit REST API). Dart only checks `isSignedIn` at startup. |
| **API integration** | SuperheroAPI search with dialog-based save flow (Save/Skip/Save All/Cancel) |
| **Local database** | SQLite via sqflite with `HeroRepository` (CRUD, caching, job queue) |
| **State management** | BLoC for theme, SHQL™ runtime for all app state |
| **Navigation** | GoRouter with SHQL™ navigation stack (`GO_TO`, `GO_BACK`, `PUSH_ROUTE`) |
| **Dark mode** | Toggle via `ThemeCubit`, persisted in SharedPreferences + Firestore |
| **Onboarding** | First-run screen with API config, filter setup, privacy consent |
| **Search with debounce** | Debounced text input in FilterEditor (apply mode) and TextField widget |
| **Swipe to delete** | `DismissibleCard` YAML template wrapping hero cards |
| **Dynamic scaling** | `LayoutBuilder`-based responsive GridView (2-6 columns based on width) |
| **Weather** | Live weather via Open-Meteo — pure SHQL™ (`REFRESH_WEATHER()` calls `FETCH()`, parses WMO codes, no Dart service) |
| **Connectivity indicator** | `ConnectivityService` shows SnackBar on network changes |
| **Localization** | `flutter_localizations` with `intl` support (`l10n/`) |
| **Accessibility** | `Semantics` labels on hero cards and interactive elements (all in YAML) |
| **README** | This document |

### Additional Requirements

| Feature | Implementation |
|---|---|
| **Firestore cloud sync** | Pure SHQL™ — `Cloud.SAVE_PREF()` wraps `SAVE_STATE` + `Cloud.SAVE()` (PATCHes Firestore REST). `Cloud.SEED_FROM_CLOUD()` loads cloud prefs at startup. |
| **API response caching** | Same-day dedup: identical search queries return cached results |
| **Location services** | `LocationService` with `geolocator` + `permission_handler` |
| **Filter predicates** | User-defined SHQL™ predicates (Heroes, Villains, Giants + custom) |
| **Statistical functions** | `Stats.height_avg`, `Stats.height_stdev` etc. — running O(1) statistics for computed filter predicates |
| **Hero amendments** | Edit hero stats/biography, locks from reconciliation |
| **Reconciliation** | Sync saved heroes with online API, diff-based updates |
| **Search history** | Persisted search history with ActionChip replay |
| **Filter editor** | Reusable filter editor with manage/apply modes (SHQL™ + YAML) |
| **Ad-hoc queries** | Type SHQL™ queries to filter heroes without saving a predicate |
| **Image caching** | `CachedImage` Dart factory (thin wrapper around `cached_network_image`) |

## Testing

```bash
cd herodex_3000
flutter test
```

Tests cover:
- Full SHQL™ orchestration: 262 tests covering all SHQL™ scripts, Dart callbacks, YAML expression coverage, reconciliation, filters, amendments, search (`shql_orchestration_test.dart`)
- Database operations (`db_test.dart`)
- Connectivity service (`connectivity_service_test.dart`)
- SHQL™-generated hero card widget trees (`hero_card_test.dart`)
- Splash screen rendering (`widget_test.dart`)

The shared packages have 340+ tests: `shql/` engine (272 tests covering parser, tokenizer, runtime, execution) and `hero_common/` (70 tests covering models, predicates, JSON parsing, sorting, amendments).

## Key Files

| File | Purpose |
|---|---|
| `lib/main.dart` | App entry point (bootstraps Firebase, SharedPreferences, runs app) |
| `lib/app.dart` | `HeroDexApp` widget — auth gate, SHQL™ wiring, Dart callback registry |
| `lib/core/hero_coordinator.dart` | Dart platform primitives: DB CRUD, reconciliation, search, edit fields, filters |
| `lib/core/herodex_widget_registry.dart` | Dart factories for third-party widgets (CachedImage, FlutterMap, TileLayer, MarkerLayer) |
| `lib/core/services/firebase_auth_service.dart` | Startup `isSignedIn` check (auth logic is in `auth.shql`) |
| `lib/core/services/firebase_service.dart` | Firebase Analytics/Crashlytics |
| `lib/core/services/connectivity_service.dart` | Network monitoring |
| `lib/core/services/location_service.dart` | GPS location |
| `lib/core/theme/theme_cubit.dart` | Dark/light theme BLoC (relay from SHQL™ via `_ON_PREF_CHANGED`) |
| `lib/persistence/sqflite_database_adapter.dart` | SQLite driver (FFI on desktop, native on mobile) |
| `assets/shql/*.shql` | 12 SHQL™ scripts: auth, navigation, firestore, preferences, statistics, filters, heroes, hero_detail, hero_cards, search, hero_edit, world |
| `assets/screens/*.yaml` | SDUI screen definitions (7 screens) |
| `assets/widgets/*.yaml` | Reusable YAML widget templates (19 templates including login, dialogs, cards) |

## API

The app uses the [Superhero API](https://superheroapi.com):

- **Search**: `GET /api/{access-token}/search/{name}`
- **Get by ID**: `GET /api/{access-token}/{id}`

The API key is stored locally and synced to Firestore. Search results are cached per-day to minimize API calls.

## License

Course project for HFL25-2 (Flutter), 2026.
