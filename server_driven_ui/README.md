# server_driven_ui

The runtime framework that sits between YAML + SHQL™ and Flutter. It turns declarative YAML definitions and SHQL™ logic into live Flutter widget trees — so that application code never has to touch Dart.

## What it does

- **`YamlUiEngine`** — Loads YAML screen and widget definitions, resolves embedded `shql:` expressions, and produces widget trees.
- **`WidgetRegistry`** — Maps YAML type names (e.g. `Text`, `Column`, `FilledButton`) to Flutter widget constructors. Also hosts YAML-defined widgets that are composable via `"prop:name"` placeholder substitution.
- **`ShqlBindings`** — Bridges the SHQL™ runtime to Flutter: exposes variables, notifies listeners on mutation, evaluates expressions. The `Observer` widget subscribes to SHQL™ variables and rebuilds automatically when they change.
- **`callShql`** — Evaluates SHQL™ expressions from user-interaction callbacks (button presses, text input, swipe gestures). Errors are caught and displayed as SnackBars rather than crashing the app.

## Design principles

- **YAML defines structure.** Screens, dialogs, and reusable components are YAML files. Props are values (strings, numbers, colors). Callback props (`on*` keys) are SHQL™ expressions.
- **SHQL™ defines behaviour.** All logic — state changes, navigation, data flow, dynamic widget tree generation — is written in SHQL™. The runtime provides built-in platform bridges (`FETCH` for HTTP GET, `POST`/`PATCH` for HTTP mutations, `SAVE_STATE`/`LOAD_STATE` for persistence, `NAVIGATE` for routing). Dart callbacks are only registered for operations that genuinely require native platform access (native dialogs, geolocation) and then wrapped in SHQL™ functions.
- **Flutter is the rendering substrate.** The `WidgetRegistry` translates YAML nodes into Flutter widgets. Application code never instantiates widgets directly — that is the framework's job.

YAML-defined widgets are composable: a screen references another widget by type name and passes props via `"prop:name"` placeholders that are substituted at build time. SHQL™ can also generate complete widget trees dynamically at runtime — the framework renders whatever tree structure SHQL™ returns.
