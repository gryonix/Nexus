#!/bin/bash
set -euo pipefail
NAME='gryonixnexus2'
MOUNT='/srv/gryonixnexus-storage2'
FIRST='/dev/sdi'
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
if ! command -v mkfs.btrfs >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -q btrfs-progs
fi
if [ "$(blkid -s LABEL -o value "$FIRST" || true)" != "$NAME" ]; then
  for disk in '/dev/sdi' '/dev/sdj'; do
    gnx_free "$disk"
  done
  for disk in '/dev/sdi' '/dev/sdj'; do
    wipefs -a -q "$disk"
  done
  mkfs.btrfs -q -f -L "$NAME" -d raid1 -m raid1 '/dev/sdi' '/dev/sdj'
  udevadm settle
fi
btrfs device scan >/dev/null
install -d "$MOUNT"
uuid="$(blkid -s UUID -o value "$FIRST")"
grep -q "UUID=$uuid $MOUNT " /etc/fstab || echo "UUID=$uuid $MOUNT btrfs defaults,nofail 0 0" >> /etc/fstab
mountpoint -q "$MOUNT" || mount "$MOUNT"
echo GRYONIXNEXUS_RAID_DONE
