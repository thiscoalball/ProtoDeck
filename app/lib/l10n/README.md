# Localization structure

The app exposes localization through `context.l10n`. `AppLocalizations` is a
small facade; user-facing copy lives in feature-sized files under `strings/`.

When localizing another feature:

1. Add a focused `<feature>_strings.dart` module instead of extending an
   unrelated or global dictionary.
2. Register that module once in `AppLocalizations`.
3. Read the module in widgets with `context.l10n.<feature>`.
4. Keep services and models language-neutral. They should return typed states,
   codes, values, and exceptions rather than presentation sentences.
5. Use stable IDs for large catalogs. The tool catalog resolves translations
   by tool ID and keeps network and developer copy in separate files.

Supported user selections are System, Simplified Chinese, and English. The
selection is persisted by `AppState` and applied to Android, Windows, and Linux
through `MaterialApp`.
