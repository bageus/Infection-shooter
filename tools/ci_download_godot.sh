#!/usr/bin/env bash
# Pinned official release; a temporary mirror outage must not abort every job.
set -euo pipefail
godot_archive_path="${1:-/tmp/godot.zip}"
godot_partial_path="${godot_archive_path}.partial.$$"
trap 'rm -f "$godot_partial_path"' EXIT
godot_asset='Godot_v4.7.2-stable_linux.x86_64.zip'
godot_sha256='cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4'
for godot_release_host in \
  'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable' \
  'https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable'; do
  if curl -fSL --retry 2 --retry-all-errors --retry-delay 2 \
      --connect-timeout 15 --max-time 120 \
      -o "$godot_partial_path" "$godot_release_host/$godot_asset" &&
      printf '%s  %s\n' "$godot_sha256" "$godot_partial_path" | sha256sum --check --status; then
    mv "$godot_partial_path" "$godot_archive_path"
    exit 0
  fi
  echo "Godot download failed validation; trying next official source." >&2
done
echo 'Unable to download the pinned Godot release from either official source.' >&2
exit 1
