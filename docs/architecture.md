# Architecture

ProtoDeck is a Flutter application with platform adapters for operations that cannot be implemented
portably. The Flutter project is located in `app/`.

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| Application shell | `lib/app.dart`, `lib/ui/app_shell.dart` | Theme, navigation and responsive layout |
| Feature pages | `lib/ui/pages/` | Presentation and user interaction |
| State | `lib/state/` | Long-lived application and task state |
| Services | `lib/services/` | Protocols, parsing, diagnostics and persistence adapters |
| Data | `lib/data/`, `lib/models/` | Drift storage and shared data structures |
| Android adapter | `android/app/src/main/kotlin/` | Network, Wi-Fi, cellular, Bluetooth and foreground work |
| Native iPerf | `android/app/src/main/cpp/` | Embedded libiperf bridge |
| Desktop runners | `windows/`, `linux/` | Host integration and packaging |

Platform communication is kept behind service adapters. Long-running operations model validation,
running, cancellation, success and failure explicitly. Unavailable platform data remains unavailable;
the UI must not replace it with plausible constants.

## Local data

Drift/SQLite stores settings, profiles, known SSH hosts, cache entries and resumable application
state. Secrets use `flutter_secure_storage` rather than ordinary database columns. The bundled IEEE
OUI database is read locally and can be replaced through the validated manual update flow.

## Development principles

- Keep protocol and calculation logic out of widgets.
- Preserve platform capability gaps instead of returning simulated values.
- Request sensitive permissions at the feature boundary.
- Bound scans, concurrency, buffers and retained messages.
- Redact credentials and secret-like query parameters from diagnostic logs.
- Add focused tests for parsers, state transitions and regression fixes.
