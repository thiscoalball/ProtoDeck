# Contributing to ProtoDeck

Thanks for helping improve ProtoDeck.

## Before opening a change

1. Search existing issues and discussions.
2. Use the bug or feature template for user-visible changes.
3. Keep a pull request focused on one problem.
4. Do not include credentials, private network data, personal device identifiers, proprietary packet
   captures or screenshots from unrelated products.

## Development setup

Install Flutter stable and the toolchain required by the target platform, then run:

```bash
cd app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Build only on a supported host: Android and Linux can be built on Linux; Windows desktop requires a
Windows host; iOS requires macOS and Xcode.

## Engineering expectations

- Never fabricate network, signal, Bluetooth, GeoIP, OUI or diagnostic data.
- Treat unavailable, denied, cached, timed out and failed as distinct states.
- Bound scans, concurrency, buffers and histories, and give long operations a stop action.
- Keep secrets in platform secure storage and redact them from logs and examples.
- Preserve unrelated working-tree changes.
- Add focused tests for parsers, calculations, state transitions and regressions.
- Update platform, permission, privacy and third-party documentation when behavior changes.

## Pull requests

Describe the problem, implementation, platforms affected, tests executed and any device-only checks
that remain. UI changes should include original screenshots with private SSIDs, addresses and account
details removed.

By submitting a contribution, you agree that it is licensed under the repository's Apache License
2.0 and that you have the right to submit it.
