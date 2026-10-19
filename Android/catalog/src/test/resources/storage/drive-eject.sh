#!/bin/bash
set -euo pipefail
DRIVE='3f2a7c1e-5b8d-4e6f-9a0b-1c2d3e4f5a6b'
MOUNT='/srv/gryonix-backup/usb1'
sync
if mountpoint -q "$MOUNT" && ! umount "$MOUNT"; then
  echo "The drive is busy. A backup may be writing to it."
  exit 3
fi
part="/dev/disk/by-uuid/$DRIVE"
if [ -b "$part" ] && command -v udisksctl >/dev/null 2>&1; then
  udisksctl power-off -b "/dev/$(lsblk -no PKNAME "$part" | head -n 1)" >/dev/null 2>&1 || true
fi
echo GRYONIXNEXUS_DRIVE_EJECT_DONE
