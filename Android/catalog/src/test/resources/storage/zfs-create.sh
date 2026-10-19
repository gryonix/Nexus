#!/bin/bash
set -euo pipefail
POOL='gryonixnexus2'
MOUNT='/srv/gryonixnexus-storage2'
gnx_expect() {
  case "$1" in
    '/dev/sdi') echo '4000787030016|WD-WCC4E1FREE1' ;;
    '/dev/sdj') echo '4000787030016|WD-WCC4E1FREE2' ;;
  esac
}
gnx_free() {
  if [ ! -b "$1" ]; then
    echo "$1 is not a disk on this server."
    exit 3
  fi
  local want size serial
  want="$(gnx_expect "$1")"
  if [ -n "$want" ]; then
    size="$(lsblk -dnbo SIZE "$1" | tr -d '[:space:]')"
    serial="$(lsblk -dno SERIAL "$1" | tr -d '[:space:]')"
    if [ "${want%%|*}" != "$size" ] || { [ -n "${want#*|}" ] && [ -n "$serial" ] && [ "${want#*|}" != "$serial" ]; }; then
      echo "$1 is not the disk the app listed. Nothing was erased."
      exit 3
    fi
  fi
  if [ -n "$(lsblk -rno MOUNTPOINT "$1" | tr -d '[:space:]')" ] || lsblk -rno TYPE "$1" | grep -E '^(raid|lvm|crypt)' >/dev/null; then
    echo "$1 is in use. Nothing was erased."
    exit 3
  fi
}
if ! command -v zpool >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if ! { rm -f /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg; DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold update -qq && DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -qq zfsutils-linux; } >/dev/null 2>&1; then
    echo "ZFS tools could not be installed here. On Debian they come from the contrib section."
    exit 3
  fi
fi
if ! modprobe zfs >/dev/null 2>&1; then
  echo "This kernel has no ZFS module. Install zfs-dkms, or pick another kind of array."
  exit 3
fi
if ! zpool list -H "$POOL" >/dev/null 2>&1; then
  for disk in '/dev/sdi' '/dev/sdj'; do
    gnx_free "$disk"
  done
  for disk in '/dev/sdi' '/dev/sdj'; do
    wipefs -a -q "$disk"
  done
  zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -m "$MOUNT" "$POOL" mirror '/dev/sdi' '/dev/sdj'
fi
zpool set cachefile=/etc/zfs/zpool.cache "$POOL" || true
echo GRYONIXNEXUS_RAID_DONE
