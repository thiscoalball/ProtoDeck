#!/usr/bin/env bash
set -euo pipefail

event_name="${1:-}"
ref_type="${2:-}"
ref_name="${3:-}"
run_number="${4:-}"
pubspec_path="${5:-app/pubspec.yaml}"
manual_version="${6:-}"

if [[ "$event_name" == "push" && "$ref_type" == "tag" ]]; then
  if [[ ! "$ref_name" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid release tag '$ref_name'. Expected vMAJOR.MINOR.PATCH, for example v0.0.1." >&2
    exit 1
  fi
  version="${ref_name#v}"
  version_source="tag"
  build_label="release"
elif [[ "$event_name" == "workflow_dispatch" ]]; then
  if [[ -n "$manual_version" ]]; then
    version="$manual_version"
    version_source="manual-input"
  else
    if [[ ! -f "$pubspec_path" ]]; then
      echo "Flutter manifest not found: $pubspec_path" >&2
      exit 1
    fi
    version_line="$(grep -m 1 -E '^version:[[:space:]]*' "$pubspec_path" || true)"
    version="${version_line#version:}"
    version="${version//[[:space:]]/}"
    version="${version%%+*}"
    version_source="pubspec"
  fi
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid manual build version '${version:-missing}'. Expected MAJOR.MINOR.PATCH." >&2
    exit 1
  fi
  build_label="debug"
else
  echo "Unsupported build trigger '$event_name' ($ref_type: $ref_name)." >&2
  exit 1
fi

if [[ ! "$run_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid build number '$run_number'. Expected a positive integer." >&2
  exit 1
fi

flutter_mode="release"
artifact_label="$version-$build_label"

echo "Resolved application version $version (Flutter mode: $flutter_mode, label: $build_label, source: $version_source, build: $run_number)."

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$version"
    echo "build_number=$run_number"
    echo "source=$version_source"
    echo "flutter_mode=$flutter_mode"
    echo "build_label=$build_label"
    echo "artifact_label=$artifact_label"
  } >> "$GITHUB_OUTPUT"
else
  echo "version=$version"
  echo "build_number=$run_number"
  echo "source=$version_source"
  echo "flutter_mode=$flutter_mode"
  echo "build_label=$build_label"
  echo "artifact_label=$artifact_label"
fi
