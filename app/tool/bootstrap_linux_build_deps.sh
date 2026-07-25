#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${app_root}/.." && pwd)"
sysroot="${repo_root}/.tooling/linux-sysroot"
debs="${sysroot}/debs"

mkdir -p "${debs}" "${sysroot}/root"

roots=(libgtk-3-dev libsecret-1-dev liblzma-dev ninja-build)
mapfile -t dependencies < <(
  apt-cache depends --recurse --important \
    --no-recommends --no-suggests --no-conflicts --no-breaks \
    --no-replaces --no-enhances "${roots[@]}" |
    sed -n -E 's/^[ |]*(Pre)?Depends: ([^ ]+).*$/\2/p' |
    tr -d '<>' |
    sed 's/:i386$//' |
    sort -u
)

declare -A seen=()
packages=("${roots[@]}" "${dependencies[@]}")
cd "${debs}"
for package in "${packages[@]}"; do
  [[ -n "${package}" ]] || continue
  [[ -z "${seen[${package}]:-}" ]] || continue
  seen["${package}"]=1
  compgen -G "${debs}/${package}_*.deb" >/dev/null && continue
  candidate="$(apt-cache policy "${package}" | sed -n -E 's/^  Candidate: (.+)$/\1/p' | head -n 1)"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]] || continue
  apt-get download "${package}=${candidate}"
done

for archive in "${debs}"/*.deb; do
  dpkg-deb -x "${archive}" "${sysroot}/root"
done

echo "Linux build sysroot ready: ${sysroot}/root"
