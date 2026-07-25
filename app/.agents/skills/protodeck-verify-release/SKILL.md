---
name: protodeck-verify-release
description: Risk-based validation and public-release hygiene for ProtoDeck Flutter/Dart, Drift, Android Kotlin/Gradle, JNI/CMake, assets, permissions and APK output. Use after code or documentation changes, when tests/builds fail, before committing or publishing the repository, when changing dependencies/generated files/native code, or when preparing a debug/release APK.
---

# Verify ProtoDeck Release

Read [test-matrix.md](references/test-matrix.md), inspect `git -C .. status --short` and review the
actual diff before choosing a tier.

## Choose the smallest sufficient tier

- Focused: format changed Dart files, run `flutter analyze --no-pub`, then directly related tests.
- Full Dart: focused checks plus the full `flutter test --no-pub` suite.
- Android APK: full Dart checks plus `flutter build apk --debug --no-pub`.
- Release candidate: Android APK checks, release signing/config review, license/notice review, secret
  scan and physical-device matrix. A build signed with debug keys is not a publishable release.

Run `scripts/verify.sh focused|full|apk` from any directory for standard checks. Pass specific test
paths after `focused` to run them after analysis.

## Review what automation cannot prove

- Confirm loading, failure, cancellation, retry, dispose and network-change behavior.
- Confirm new UI at narrow phone, large text, dark theme and responsive widths.
- Confirm permissions, Wi-Fi scan, cellular, Bluetooth, foreground work, native library loading and
  peer interoperability on physical Android devices.
- Inspect generated code only through its source/schema and generator command.
- Check that no build output, credential, API key, host address, local absolute path, personal name,
  email, device identifier or internal endpoint is being published.

## Preserve legitimate attribution

Remove competitor comparisons and local/private context from the public product repository. Keep
licenses, copyright notices and attribution required by embedded/open-source dependencies and data
sources. Never present third-party code or data as original project code.

## Report accurately

List commands that passed, failed or were skipped. Separate compile/unit confidence from emulator and
physical-device confidence. Do not declare a native or radio feature verified only because Dart tests
passed.
