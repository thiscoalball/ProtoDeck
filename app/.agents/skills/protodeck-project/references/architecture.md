# Current architecture map

## Repository and toolchain

- Git root: the directory containing `.git`
- Flutter app: `app`
- Local toolchain: `.tooling/{flutter,jdk,android-sdk}` at repository root
- Environment bootstrap: `source ../android-env.sh`
- Android: minimum API 29, Java/Kotlin 17, CMake 3.22.1, target/compile SDK from Flutter
- Flutter stack: Material 3, go_router, Riverpod, Drift, SharedPreferences, secure storage

## Runtime structure

| Area | Owning paths |
|---|---|
| Bootstrap/router/theme | `lib/main.dart`, `lib/app.dart`, `lib/ui/app_shell.dart` |
| Tool discovery and categories | `lib/ui/tool_catalog.dart`, `lib/ui/tool_launcher.dart` |
| Professional developer workbenches | `lib/ui/pages/tools/*_workbench_page.dart`, `lib/services/*_workbench_service.dart` |
| Pages | `lib/ui/pages/**` |
| Reusable UI | `lib/ui/widgets/**` |
| Pure/protocol services | `lib/services/**` |
| Cross-feature data | `lib/models/**` |
| App state/providers | `lib/state/**` |
| Drift database | `lib/data/app_database.dart` plus generated `.g.dart` |
| Offline IEEE OUI | `lib/core/oui/**`, `tool/oui/**`, `assets/data/ieee_oui.db` |
| Android bridge | `android/app/src/main/kotlin/com/nettools/nettools_mobile/**` |
| iPerf native layer | `android/app/src/main/cpp/**` |
| Tests | `test/**` |

The current Android method channel is `nettools/native`. Dart-facing network methods live in
`NativeNetworkService`; SMB and Bluetooth have their own Dart services but share the channel handler
in `MainActivity.kt`.

## Persistence

`AppDatabase` owns tool sessions, saved remote profiles, known SSH hosts, GeoIP cache, settings and
transfer jobs. Tool history is deliberately disabled in `AppState`: old rows are preserved but not
loaded or newly written. Do not infer that an existing table must be visible in navigation.

Secrets must remain outside ordinary Drift rows. Store only a secure-storage reference in a profile.
Known SSH host fingerprints belong in `KnownHosts` and use TOFU behavior.

## Documentation boundary

Keep public documentation focused on this product's behavior, architecture, setup and licenses. Do
not add competitor comparisons, private environment details or local absolute paths.

## Common commands

```bash
source ../android-env.sh
../.tooling/flutter/bin/flutter analyze --no-pub
../.tooling/flutter/bin/flutter test --no-pub
../.tooling/flutter/bin/flutter build apk --release --no-pub
```

Use the release-verification skill rather than running every expensive command for every tiny edit.
