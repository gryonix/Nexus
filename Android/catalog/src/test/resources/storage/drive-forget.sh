#!/bin/bash
set -euo pipefail
DRIVE='3f2a7c1e-5b8d-4e6f-9a0b-1c2d3e4f5a6b'
MOUNT='/srv/gryonix-backup/usb1'
if mountpoint -q "$MOUNT" && ! umount "$MOUNT"; then
  echo "The drive is busy. A backup may be writing to it."
  exit 3
fi
awk -v m="$MOUNT" -v u="UUID=$DRIVE" '$1 != u && $2 != m' /etc/fstab > /etc/fstab.gryonixnexus
cat /etc/fstab.gryonixnexus > /etc/fstab
rm -f /etc/fstab.gryonixnexus
systemctl daemon-reload >/dev/null 2>&1 || true
rmdir "$MOUNT" 2>/dev/null || true
echo GRYONIXNEXUS_DRIVE_FORGET_DONE
