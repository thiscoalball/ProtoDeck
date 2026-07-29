#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${app_root}/.." && pwd)"
build_sysroot="${repo_root}/.tooling/linux-sysroot/root"
flutter_bin="${repo_root}/.tooling/flutter/bin/flutter"

if [[ ! -x "${flutter_bin}" ]]; then
  echo "Flutter SDK not found under ../.tooling/flutter." >&2
  exit 1
fi
if [[ ! -x "${build_sysroot}/usr/bin/ninja" ]]; then
  echo "Linux sysroot is missing. Run ./tool/bootstrap_linux_build_deps.sh first." >&2
  exit 1
fi

mkdir -p "${repo_root}/.tooling/config"
export XDG_CONFIG_HOME="${repo_root}/.tooling/config"
export PATH="${build_sysroot}/usr/bin:${PATH}"
export PKG_CONFIG_SYSROOT_DIR="${build_sysroot}"
export PKG_CONFIG_PATH="${build_sysroot}/usr/lib/x86_64-linux-gnu/pkgconfig:${build_sysroot}/usr/lib/pkgconfig:${build_sysroot}/usr/share/pkgconfig"
export C_INCLUDE_PATH="${build_sysroot}/usr/include:${build_sysroot}/usr/include/x86_64-linux-gnu"
export CPLUS_INCLUDE_PATH="${C_INCLUDE_PATH}"
export LIBRARY_PATH="${build_sysroot}/usr/lib/x86_64-linux-gnu:${build_sysroot}/usr/lib"

cd "${app_root}"
"${flutter_bin}" --suppress-analytics build linux --release --no-pub "$@"
"${app_root}/tool/build_bundled_iperf_linux.sh"
tar -C build/linux/x64/release -czf build/ProtoDeck-linux-x64.tar.gz bundle

echo "Linux release: ${app_root}/build/ProtoDeck-linux-x64.tar.gz"
