#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

upstream="https://raw.githubusercontent.com/matosimi/atari-fontmaker/e2a9adbb23bab2aa94ffcaa6e51db384311986a9/Resources"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fetch_resource() {
    local upstream_name="$1" local_name="$2" checksum="$3"
    local target="Resources/$local_name"
    if [[ -f "$target" ]] && printf '%s  %s\n' "$checksum" "$target" | shasum -a 256 -c --status; then
        return
    fi
    curl --fail --silent --show-error --location "$upstream/$upstream_name" --output "$temp_dir/$local_name"
    printf '%s  %s\n' "$checksum" "$temp_dir/$local_name" | shasum -a 256 -c --status
    mv "$temp_dir/$local_name" "$target"
}

fetch_resource Default.fnt Default.fnt 006e821c086a41874f04ec86e7b2298529ef16a74276ca660c4e766d3a371342
fetch_resource altirraPAL.pal Atari.pal 565f00fb85bf972da3fe343a0f97bcb624b0526e97a77a826d1f4132f1a2534f
