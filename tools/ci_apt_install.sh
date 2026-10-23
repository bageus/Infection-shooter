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
src_opts=()
for attempt in 1 2 3; do
  if [ -f "$ubuntu_sources" ]; then
    src_opts=(-o "Dir::Etc::sourcelist=$ubuntu_sources" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0)
    if [ "$attempt" = 2 ]; then
      # The image's default mirror can trickle a single large package for minutes; try the main archive.
      sed 's#^URIs: mirror+file:.*#URIs: http://archive.ubuntu.com/ubuntu/#; s#//azure\.archive\.ubuntu\.com#//archive.ubuntu.com#' "$ubuntu_sources" > /tmp/ci-ubuntu.sources
      src_opts=(-o "Dir::Etc::sourcelist=/tmp/ci-ubuntu.sources" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0)
    fi
  fi
  if timeout -k 5 60 sudo apt-get "${apt_opts[@]}" "${src_opts[@]}" update -q &&
      timeout -k 5 180 sudo apt-get "${apt_opts[@]}" "${src_opts[@]}" install -y -q --no-install-recommends "$@"; then
    exit 0
  fi
  echo "apt attempt $attempt failed" >&2
  sleep 5
done
exit 1
