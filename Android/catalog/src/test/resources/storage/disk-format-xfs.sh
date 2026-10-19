#!/bin/bash
set -euo pipefail
DISK='/dev/sdj'
LABEL='gnx-sdj'
MOUNT='/srv/disk-sdj'
gnx_free() {
  if [ ! -b "$1" ]; then
    echo "$1 is not a disk on this server."
    exit 3
  fi
  if [ -n "$(lsblk -rno MOUNTPOINT "$1" | tr -d '[:space:]')" ] || lsblk -rno TYPE "$1" | grep -E '^(raid|lvm|crypt)' >/dev/null; then
    echo "$1 is in use. Nothing was erased."
    exit 3
  fi
}
if ! command -v mkfs.xfs >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -q xfsprogs
fi
if ! lsblk -rno LABEL "$DISK" | grep -qx -- "$LABEL"; then
  gnx_free "$DISK"
  for old in $(lsblk -rnpo NAME,TYPE "$DISK" | awk '$2 == "part" {print $1}'); do
    zpool labelclear -f "$old" >/dev/null 2>&1 || true
    wipefs -a -q "$old" || true
  done
  zpool labelclear -f "$DISK" >/dev/null 2>&1 || true
  wipefs -a -q "$DISK"
  size="$(blockdev --getsz "$DISK")"
  dd if=/dev/zero of="$DISK" bs=512 seek="$((size - 8192))" count=8192 conv=fsync status=none
  printf 'label: gpt\n,,L\n' | sfdisk -q "$DISK"
  udevadm settle
  part="$(lsblk -rnpo NAME,TYPE "$DISK" | awk '$2 == "part" {print $1; exit}')"
  mkfs.xfs -f -q -L "$LABEL" "$part"
  udevadm settle
fi
part="$(lsblk -rnpo NAME,LABEL "$DISK" | awk -v l="$LABEL" '$2 == l {print $1; exit}')"
install -d "$MOUNT"
uuid="$(blkid -s UUID -o value "$part")"
grep -q "UUID=$uuid $MOUNT " /etc/fstab || echo "UUID=$uuid $MOUNT xfs defaults,nofail 0 0" >> /etc/fstab
mountpoint -q "$MOUNT" || mount "$MOUNT"
echo GRYONIXNEXUS_DISK_FORMAT_DONE
