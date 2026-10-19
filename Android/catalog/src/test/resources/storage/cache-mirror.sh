#!/bin/bash
set -euo pipefail
ARRAY='/dev/md/gnx-fast'
gnx_expect() {
  case "$1" in
    '/dev/nvme0n1') echo '256060514304|' ;;
    '/dev/sdd') echo '1000204886016|' ;;
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
if ! command -v mdadm >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -q mdadm
fi
if [ ! -e "$ARRAY" ]; then
  for disk in '/dev/nvme0n1' '/dev/sdd'; do
    gnx_free "$disk"
  done
  for disk in '/dev/nvme0n1' '/dev/sdd'; do
    wipefs -a -q "$disk"
  done
  mdadm --create "$ARRAY" --name=gnx-fast --metadata=1.2 --run --level=1 --raid-devices=2 '/dev/nvme0n1' '/dev/sdd'
  wipefs -a -q "$ARRAY"
  install -d /etc/mdadm
  mdadm --detail --brief "$ARRAY" >> /etc/mdadm/mdadm.conf
  update-initramfs -u >/dev/null 2>&1 || true
fi
echo GRYONIXNEXUS_RAID_DONE
