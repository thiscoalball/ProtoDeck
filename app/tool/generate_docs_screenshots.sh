#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
export FLUTTER_SUPPRESS_ANALYTICS=true

cd "$app_root"
"$flutter_bin" --no-version-check test --no-pub --update-goldens \
  test/screenshots/documentation_screenshots_test.dart

base_screenshots=(
  android-home.png
  android-wifi.png
  android-tools.png
  android-ping.png
  android-network-doctor.png
  android-json-workbench.png
  android-api-workbench.png
  android-remote.png
  android-settings.png
  desktop-home.png
  desktop-tools.png
  desktop-api-workbench.png
  desktop-remote.png
)

for screenshot in "${base_screenshots[@]}"; do
  for suffix in "" "-zh"; do
    localized="${screenshot%.png}${suffix}.png"
    if [[ ! -s "$app_root/../docs/screenshots/$localized" ]]; then
      echo "Screenshot was not generated: $localized" >&2
      exit 1
    fi
  done
done

echo "Documentation screenshots generated in ../docs/screenshots"
