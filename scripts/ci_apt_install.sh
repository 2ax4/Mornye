#!/usr/bin/env bash
# Installs apt packages on CI runners, retrying around transient mirror
# outages. The GitHub-hosted Ubuntu images resolve package indexes through
# the Azure mirror (mirror+file:/etc/apt/apt-mirrors.txt), which
# occasionally fails DNS resolution for minutes at a time and kills builds
# at the dependency step with "Temporary failure resolving
# 'azure.archive.ubuntu.com'". Retrying the whole update+install pair after
# a pause outlives those outages.
#
# Usage: ci_apt_install.sh package...
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 package..." >&2
  exit 2
fi

# Acquire::Retries re-fetches each index and archive on its own; the outer
# loop below retries the whole pair when even that is not enough.
apt_options=(
  -o Acquire::Retries=5
  -o Acquire::http::Timeout=20
  -o Acquire::https::Timeout=20
)

for attempt in 1 2 3; do
  echo "::group::apt-get attempt ${attempt}/3: $*"
  if sudo apt-get update "${apt_options[@]}" &&
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      "${apt_options[@]}" "$@"; then
    echo "::endgroup::"
    exit 0
  fi
  echo "::endgroup::"
  # Transient DNS outages usually clear within a minute or two.
  [ "$attempt" -lt 3 ] && sleep 30
done

echo "::error::apt-get failed after 3 attempts for: $*" >&2
exit 1
