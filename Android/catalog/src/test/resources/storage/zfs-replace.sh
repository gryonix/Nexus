#!/bin/bash
set -euo pipefail
POOL='tank'
OLD='9147389209417539263'
NEW='/dev/sdj'
gnx_expect() {
  case "$1" in
    '/dev/sdj') echo '1000204886016|' ;;
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
if ! zpool status -LP "$POOL" | grep -q "$NEW"; then
  gnx_free "$NEW"
  wipefs -a -q "$NEW"
  zpool replace -f "$POOL" "$OLD" "$NEW"
fi
echo GRYONIXNEXUS_RAID_REPAIR_DONE
