#!/bin/bash
set -euo pipefail
ARRAY='/dev/md127'
NEW='/dev/sdi'
gnx_expect() {
  case "$1" in
    '/dev/sdi') echo '4000787030016|WD-WCC4E1FREE1' ;;
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
CHECK=('/dev/sdb' '/dev/sdc')
if command -v smartctl >/dev/null 2>&1; then
  for disk in "${CHECK[@]}"; do
    if smartctl -H "$disk" 2>/dev/null | grep -q FAILED; then
      echo "$disk reports that it is failing. Replace that disk first."
      exit 3
    fi
  done
fi
if mdadm --detail "$ARRAY" | grep -Eq 'State : .*(degraded|recovering|resyncing|reshaping)'; then
  echo "The array is not healthy right now. Wait until it is, then try again."
  exit 3
fi
if ! mdadm --detail "$ARRAY" | grep -qw -- "$NEW"; then
  gnx_free "$NEW"
  wipefs -a -q "$NEW"
  mdadm "$ARRAY" --add "$NEW"
fi
if [ "$(mdadm --detail "$ARRAY" | awk '/Raid Devices :/ {print $4}')" -lt 3 ]; then
  mdadm --grow "$ARRAY" --raid-devices=3
fi
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
