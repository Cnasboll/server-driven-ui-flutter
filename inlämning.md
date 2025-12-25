# HeroDex 3000 — Inlämning HFL25-2 (Flutter)

Repo: `https://github.com/Cnasboll/server-driven-ui-flutter/`

Projektet: `https://github.com/Cnasboll/server-driven-ui-flutter/tree/main/herodex_3000`

README: `https://github.com/Cnasboll/server-driven-ui-flutter/blob/main/herodex_3000/README.md`

## Körinstruktion

```bash
git clone https://github.com/Cnasboll/server-driven-ui-flutter/
cd server-driven-ui-flutter

# Get dependencies for all packages
cd hero_common && dart pub get && cd ..
cd shql && dart pub get && cd ..
cd server_driven_ui && flutter pub get && cd ..
cd herodex_3000 && flutter pub get

# Run the app
flutter run
```

Appen har testats på Android-emulator (Medium Phone API 36.0) och Windows (windows-desktop).
