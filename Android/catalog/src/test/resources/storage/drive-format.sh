#!/bin/bash
set -euo pipefail
DISK='/dev/sdf'
LABEL='gnxb-usb1'
MOUNT='/srv/gryonix-backup/usb1'
gnx_expect() {
  case "$1" in
    '/dev/sdf') echo '61530439680|4C530001' ;;
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
removable="$(lsblk -dno TRAN,RM,HOTPLUG "$DISK" | tr -s ' ')"
case " $removable " in
  *" usb "*|*" 1 "*) ;;
  *) echo "$DISK is not a removable drive. Nothing was erased."; exit 3 ;;
esac
for held in $(lsblk -rno MOUNTPOINT "$DISK" | grep '^/srv/gryonix-backup/' || true); do
  umount "$held"
done
gnx_free "$DISK"
for old in $(lsblk -rnpo NAME,TYPE "$DISK" | awk '$2 == "part" {print $1}'); do
  wipefs -a -q "$old" || true
done
wipefs -a -q "$DISK"
printf 'label: gpt\n,,L\n' | sfdisk -q "$DISK"
udevadm settle
part="$(lsblk -rnpo NAME,TYPE "$DISK" | awk '$2 == "part" {print $1; exit}')"
mkfs.ext4 -q -F -L "$LABEL" "$part"
udevadm settle
uuid="$(blkid -s UUID -o value "$part")"
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
echo GRYONIXNEXUS_DRIVE_FORMAT_DONE
