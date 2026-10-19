#!/bin/bash
set -euo pipefail
DRIVE='3f2a7c1e-5b8d-4e6f-9a0b-1c2d3e4f5a6b'
MOUNT='/srv/gryonix-backup/usb1'
part="/dev/disk/by-uuid/$DRIVE"
if [ ! -b "$part" ]; then
  echo "The drive is not plugged in."
  exit 3
fi
if [ "$(blkid -s TYPE -o value "$part")" != ext4 ]; then
  echo "The drive is not prepared for backups. Format it first."
  exit 3
fi
uuid="$DRIVE"
install -d -m 700 "$MOUNT"
awk -v m="$MOUNT" -v u="UUID=$uuid" '$1 != u && $2 != m' /etc/fstab > /etc/fstab.gryonixnexus
cat /etc/fstab.gryonixnexus > /etc/fstab
rm -f /etc/fstab.gryonixnexus
device="$(systemd-escape -p --suffix=device "/dev/disk/by-uuid/$uuid")"
echo "UUID=$uuid $MOUNT ext4 nofail,noatime,x-systemd.device-timeout=5s,x-systemd.wanted-by=$device 0 2" >> /etc/fstab
systemctl daemon-reload >/dev/null 2>&1 || true
mountpoint -q "$MOUNT" || mount "$MOUNT"
chmod 700 "$MOUNT"
printf '%s\n' "$uuid" > "$MOUNT/.gryonix-backup-drive"
echo "GRYONIXNEXUS_DRIVE_UUID $uuid"
echo GRYONIXNEXUS_DRIVE_ATTACH_DONE
