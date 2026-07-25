#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${app_root}/.." && pwd)"
iperf_source="${app_root}/android/app/src/main/cpp/iperf"
iperf_build="${repo_root}/.tooling/iperf-linux-build"
bundle_dir="${1:-${app_root}/build/linux/x64/release/bundle}"

if [[ -e "${iperf_source}/src/iperf_config.h" || -e "${iperf_source}/src/version.h" ]]; then
  echo "Generated target headers must not exist in the shared iPerf source tree." >&2
  exit 1
fi
if [[ ! -d "${bundle_dir}" ]]; then
  echo "Linux Flutter bundle not found: ${bundle_dir}" >&2
  exit 1
fi

mkdir -p "${iperf_build}"
cd "${iperf_build}"
"${iperf_source}/configure" \
  --enable-static-bin \
  --disable-shared \
  --without-openssl \
  --disable-profiling
make -j2 -C src iperf3

install -m 755 "${iperf_build}/src/iperf3" "${bundle_dir}/iperf3"
strip --strip-unneeded "${bundle_dir}/iperf3"
mkdir -p "${bundle_dir}/licenses"
install -m 644 "${iperf_source}/LICENSE" \
  "${bundle_dir}/licenses/iperf3-LICENSE.txt"
"${bundle_dir}/iperf3" --version
