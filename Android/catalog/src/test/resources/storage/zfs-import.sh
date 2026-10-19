#!/bin/bash
set -euo pipefail
POOL='tank'
ID='15437563216592283341'
if ! command -v zpool >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if ! { rm -f /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg; DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold update -qq && DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -qq zfsutils-linux; } >/dev/null 2>&1; then
    echo "ZFS tools could not be installed here. On Debian they come from the contrib section."
    exit 3
  fi
fi
if ! zpool list -H "$POOL" >/dev/null 2>&1; then
  zpool import -f "$ID"
fi
zpool set cachefile=/etc/zfs/zpool.cache "$POOL" || true
echo GRYONIXNEXUS_RAID_IMPORT_DONE
