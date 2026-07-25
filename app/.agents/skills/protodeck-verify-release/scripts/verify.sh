#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "$script_dir/../../../.." && pwd)"
repo_dir="$(cd "$app_dir/.." && pwd)"

if [[ -f "$repo_dir/android-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$repo_dir/android-env.sh"
fi

flutter_bin="$repo_dir/.tooling/flutter/bin/flutter"
if [[ ! -x "$flutter_bin" ]]; then
  flutter_bin="$(command -v flutter || true)"
fi
if [[ -z "$flutter_bin" ]]; then
  echo "Flutter was not found. Install it or provide the repository-local toolchain." >&2
  exit 2
fi

mode="${1:-focused}"
shift || true
cd "$app_dir"

"$flutter_bin" analyze --no-pub

case "$mode" in
  focused)
    if (($# > 0)); then
      "$flutter_bin" test --no-pub "$@"
    fi
    ;;
  full)
    "$flutter_bin" test --no-pub
    ;;
  apk)
    "$flutter_bin" test --no-pub
    "$flutter_bin" build apk --debug --no-pub
    ;;
  *)
    echo "Usage: verify.sh [focused [test paths...]]|full|apk" >&2
    exit 2
    ;;
esac
