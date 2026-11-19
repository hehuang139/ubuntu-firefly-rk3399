#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
image=${FIREFLY_BUILDER:-firefly-ubuntu22-builder:20261103}
run() { docker run --rm "$1" -v "$PWD:/build" -w /build "$image" "${@:2}"; }
fetch() {
    mkdir -p downloads records
    base=https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release
    for file in SHA256SUMS SHA256SUMS.gpg ubuntu-base-22.04.5-base-arm64.tar.gz; do
        curl -fsSL --retry 3 "$base/$file" -o "downloads/$file.new"
        mv "downloads/$file.new" "downloads/$file"
    done
    gpgv --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg downloads/SHA256SUMS.gpg downloads/SHA256SUMS 2>records/ubuntu-base-signature.txt
    printf '%s  %s\n' 075d4abd2817a5023ab0a82f5cb314c5ec0aa64a9c0b40fd3154ca3bfdae979f downloads/ubuntu-base-22.04.5-base-arm64.tar.gz | sha256sum -c -
}
rootfs() {
    mkdir -p records work
    run --privileged bash scripts/build-rootfs.sh
}
finalize() { run --privileged bash scripts/finalize-rootfs.sh; }
assemble() {
    mkdir -p outputs
    run --network=none bash scripts/assemble.sh sd
    run --network=none bash scripts/assemble.sh emmc
}
compress() {
    local img dest rc=0
    local -a jobs=()
    cd outputs
    for img in firefly-rk3399-ubuntu-22.04-gnome-arm64-{sd,emmc}-vsel1-test2.img; do
      [[ -f $img && ! -e $img.gz && ! -L $img.gz ]]
    done
    for img in firefly-rk3399-ubuntu-22.04-gnome-arm64-{sd,emmc}-vsel1-test2.img; do
      (
          dest="$img.gz.tmp"
          if command -v pigz >/dev/null; then pigz -p 6 -n -3 -c "$img" > "$dest"; else gzip -n -1 -c "$img" > "$dest"; fi
          gzip -t "$dest"
          mv "$dest" "$img.gz"
      ) &
      jobs+=("$!")
    done
    for pid in "${jobs[@]}"; do wait "$pid" || rc=1; done
    (( rc == 0 ))
    sha256sum firefly-rk3399-ubuntu-22.04-gnome-arm64-{sd,emmc}-vsel1-test2.img{,.gz} > SHA256SUMS.vsel1-test2.tmp
    mv -fT -- SHA256SUMS.vsel1-test2.tmp SHA256SUMS.vsel1-test2
}
case ${1:-help} in
    fetch) fetch ;;
    rootfs) rootfs ;;
    finalize) finalize ;;
    image) assemble ;;
    compress) compress ;;
    all) fetch; rootfs; finalize; assemble; compress ;;
    help) printf 'Usage: %s {all|fetch|rootfs|finalize|image|compress}\n' "$0" ;;
    *) exit 2 ;;
esac
