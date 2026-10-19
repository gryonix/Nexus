#!/bin/bash
set -uo pipefail
DRIVE='3f2a7c1e-5b8d-4e6f-9a0b-1c2d3e4f5a6b'
MOUNT='/srv/gryonix-backup/usb1'
part="/dev/disk/by-uuid/$DRIVE"
if [ ! -b "$part" ]; then
  echo "The drive is not plugged in."
  exit 3
fi
disk="/dev/$(lsblk -no PKNAME "$part" | head -n 1)"
case "$(smartctl -d sat -H "$disk" 2>/dev/null || true)" in
  *PASSED*) echo "GRYONIXNEXUS_DRIVE_SMART passed" ;;
  *FAILED*) echo "GRYONIXNEXUS_DRIVE_SMART failed" ;;
  *) echo "GRYONIXNEXUS_DRIVE_SMART none" ;;
esac
remount=0
if mountpoint -q "$MOUNT"; then
  sync
  if umount "$MOUNT" 2>/dev/null; then remount=1; fi
fi
if mountpoint -q "$MOUNT"; then
  echo "GRYONIXNEXUS_DRIVE_FSCK busy"
elif e2fsck -fn "$part" >/dev/null 2>&1; then
  echo "GRYONIXNEXUS_DRIVE_FSCK clean"
else
  echo "GRYONIXNEXUS_DRIVE_FSCK errors"
fi
if [ "$remount" -eq 1 ]; then mount "$MOUNT" || true; fi
if mountpoint -q "$MOUNT"; then
  probe="$MOUNT/.gnx-speed"
  start="$(date +%s%N)"
  if dd if=/dev/zero of="$probe" bs=1M count=64 oflag=direct status=none 2>/dev/null; then
    mid="$(date +%s%N)"
    dd if="$probe" of=/dev/null bs=1M iflag=direct status=none 2>/dev/null || true
    end="$(date +%s%N)"
    echo "GRYONIXNEXUS_DRIVE_SPEED $((67108864 * 1000000000 / (mid - start + 1))) $((67108864 * 1000000000 / (end - mid + 1)))"
  else
    echo "GRYONIXNEXUS_DRIVE_SPEED 0 0"
  fi
  rm -f "$probe"
fi
echo GRYONIXNEXUS_DRIVE_CHECK_DONE
