# HeroDex 3000

A Flutter application for tracking superheroes and villains, built as a showcase for **SHQL™** (a general-purpose, imperative scripting language) and **Server-Driven UI** (SDUI) architecture. The entire UI is defined in YAML files and rendered at runtime, with business logic written in SHQL™ scripts.

## Architecture

### Server-Driven UI (SDUI)

All screens are defined as YAML files in `assets/screens/`. At runtime the `YamlUiEngine` resolves SHQL™ expressions in the YAML, and the `WidgetRegistry` maps type names to Flutter widgets. This means the UI can be updated without recompiling the app.

```
assets/screens/home.yaml       -> Home dashboard
assets/screens/online.yaml     -> Online hero search
assets/screens/heroes.yaml     -> Saved heroes database
assets/screens/settings.yaml   -> Settings & preferences
assets/screens/onboarding.yaml -> First-run setup
assets/screens/hero_detail.yaml -> Hero detail view
assets/screens/hero_edit.yaml   -> Hero amendment editor
```

### SHQL™ (Small, Handy, Quintessential Language™)

SHQL™ is a general-purpose scripting language with variables, functions, loops, conditionals, and object access via dot notation. Each word actually describes the language well — it's small (lightweight), handy (practical, embedded in YAML for UI), and quintessential (it captures the essence of what you need for expression evaluation and state management). It has lambdas, loops, object literals, and drives an entire server-driven UI framework. Plus "Quintessential" is just a great word that nobody uses enough.

It runs inside a `Runtime` with a `ConstantsSet` (interned identifiers).

- **`shql/`** — The language engine: parser, tokenizer, execution nodes, runtime
- **`assets/shql/herodex.shql`** — All app business logic: navigation, filters, search, statistics
- **`shql/assets/stdlib.shql`** — Standard library (SET, LOAD_STATE, SAVE_STATE, etc.)

Key SHQL™ patterns:
- `shql: _variable` — Bind a widget prop to a reactive variable
- `shql: FUNCTION(args)` — Call an SHQL™ function (e.g. `SEARCH_HEROES(query)`)
- `Observer` widget — Subscribes to SHQL™ variables and rebuilds on change
- `boundValues` — Pass Dart values to SHQL™ without string escaping

### Mono-repo structure

```
herodex_3000/     — Flutter mobile app (this package)
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

- **BLoC** (`flutter_bloc`) for theme management (`ThemeCubit`)
- **SHQL™ runtime variables** for all app state (reactive via `Observer` and `ShqlBindings.addListener`)
- **SharedPreferences** for local persistence
- **Firestore REST API** for cloud sync of preferences

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
| **Firebase Auth** | REST-based sign-in/register gate (`FirebaseAuthService`). Without login, no app to use. |
| **API integration** | SuperheroAPI search with dialog-based save flow (Save/Skip/Save All/Cancel) |
| **Local database** | SQLite via sqflite with `HeroRepository` (CRUD, caching, job queue) |
| **State management** | BLoC for theme, SHQL™ runtime for all app state |
| **Navigation** | GoRouter with SHQL™ navigation stack (`GO_TO`, `GO_BACK`, `PUSH_ROUTE`) |
| **Dark mode** | Toggle via `ThemeCubit`, persisted in SharedPreferences + Firestore |
| **Onboarding** | First-run screen with API config, filter setup, privacy consent |
| **Search with debounce** | Debounced text input in FilterEditor (apply mode) and TextField widget |
| **Swipe to delete** | `Dismissible` wrapper on HeroCard for saved heroes |
| **Dynamic scaling** | `LayoutBuilder`-based responsive GridView (2-6 columns based on width) |
| **Connectivity indicator** | `ConnectivityService` shows SnackBar on network changes |
| **Localization** | `flutter_localizations` with `intl` support (`l10n/`) |
| **Accessibility** | `Semantics` labels on HeroCard, interactive elements |
| **README** | This document |

### Additional Requirements

| Feature | Implementation |
|---|---|
| **Firestore cloud sync** | `FirestorePreferencesService` syncs preferences via REST API |
| **API response caching** | Same-day dedup: identical search queries return cached results |
| **Location services** | `LocationService` with `geolocator` + `permission_handler` |
| **Filter predicates** | User-defined SHQL™ predicates (Heroes, Villains, Giants + custom) |
| **Statistical functions** | `STAT_AVG`, `STAT_STDEV` for computed predicates |
| **Hero amendments** | Edit hero stats/biography, locks from reconciliation |
| **Reconciliation** | Sync saved heroes with online API, diff-based updates |
| **Search history** | Persisted search history with ActionChip replay |
| **Filter editor** | Reusable `FilterEditor` widget with manage/apply modes |
| **Ad-hoc queries** | Type SHQL™ queries to filter heroes without saving a predicate |
| **Image caching** | `cached_network_image` for hero images |

## Testing

```bash
cd herodex_3000
flutter test
```

Tests cover:
- Database operations (`db_test.dart`)
- Connectivity service (`connectivity_service_test.dart`)
- HeroCard widget (`hero_card_test.dart`)
- Theme cubit (`theme_cubit_test.dart`)

The shared `hero_common` package has 245+ tests covering models, predicates, JSON parsing, sorting, and the SHQL™ engine.

## Key Files

| File | Purpose |
|---|---|
| `lib/main.dart` | App entry point (bootstraps Firebase, SharedPreferences, runs app) |
| `lib/app.dart` | `HeroDexApp` widget — auth gate, SHQL™ wiring, widget registry |
| `lib/core/services/firebase_auth_service.dart` | Firebase Auth via REST |
| `lib/core/services/firebase_service.dart` | Firebase Analytics/Crashlytics |
| `lib/core/services/firestore_preferences_service.dart` | Firestore cloud sync |
| `lib/core/services/connectivity_service.dart` | Network monitoring |
| `lib/core/services/location_service.dart` | GPS location |
| `lib/core/services/hero_search_service.dart` | Online hero search + save flow |
| `lib/core/theme/theme_cubit.dart` | Dark/light theme BLoC |
| `lib/widgets/hero_card.dart` | Hero card widget with swipe-to-delete |
| `lib/persistence/sqflite_database_adapter.dart` | SQLite driver |
| `assets/shql/herodex.shql` | All SHQL™ business logic |
| `assets/screens/*.yaml` | SDUI screen definitions |

## API

The app uses the [Superhero API](https://superheroapi.com):

- **Search**: `GET /api/{access-token}/search/{name}`
- **Get by ID**: `GET /api/{access-token}/{id}`

The API key is stored locally and synced to Firestore. Search results are cached per-day to minimize API calls.

## License

Course project for HFL25-2 (Flutter), 2026.
