#!/usr/bin/env bash
# Install apt packages on a CI runner without letting one stalled repository hang the job.
# `apt-get update` also contacts every third-party source baked into the runner image, and a
# silent stall there burned the whole job; only the Ubuntu archive is needed for these packages.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg -s "$@" >/dev/null 2>&1 && exit 0
apt_opts=(-o Acquire::ForceIPv4=true -o Acquire::Retries=2 -o Acquire::http::Timeout=20
  -o Acquire::https::Timeout=20 -o DPkg::Lock::Timeout=60)
ubuntu_sources=/etc/apt/sources.list.d/ubuntu.sources
update_opts=()
if [ -f "$ubuntu_sources" ]; then
  update_opts=(-o "Dir::Etc::sourcelist=$ubuntu_sources" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0)
fi
for attempt in 1 2 3; do
  if [ "$attempt" = 3 ] && [ -f "$ubuntu_sources" ]; then
    # Last attempt: a different mirror than the image default.
    mirror_sources=/tmp/ci-ubuntu.sources
    sed 's#//azure\.archive\.ubuntu\.com#//archive.ubuntu.com#' "$ubuntu_sources" > "$mirror_sources"
    update_opts=(-o "Dir::Etc::sourcelist=$mirror_sources" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0)
  fi
  if timeout -k 5 60 sudo apt-get "${apt_opts[@]}" "${update_opts[@]}" update -q &&
      timeout -k 5 120 sudo apt-get "${apt_opts[@]}" install -y -q --no-install-recommends "$@"; then
    exit 0
  fi
  echo "apt attempt $attempt failed" >&2
  sleep 5
done
exit 1
