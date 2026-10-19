#!/bin/bash
set -euo pipefail
MOUNT='/srv/data'
if ! mountpoint -q "$MOUNT"; then
  echo "$MOUNT is not mounted."
  exit 3
fi
if [ -n "$MOUNT" ] && command -v docker >/dev/null 2>&1; then
  for c in $(docker ps -aq); do
    if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$c" | grep -qF -- "$MOUNT"; then
      echo "Services keep their data here. Move or remove them first."
      exit 3
    fi
  done
fi
REAL="$(btrfs filesystem show "$MOUNT" | awk '$NF ~ /^\/dev\// {print $NF}')"
for disk in '/dev/sdg' '/dev/sdh'; do
  if ! printf '%s\n' "$REAL" | grep -qxF -- "$disk"; then
    echo "$disk is not in this filesystem."
    exit 3
  fi
done
umount "$MOUNT"
awk -v m="$MOUNT" '$2 != m' /etc/fstab > /etc/fstab.gryonixnexus
cat /etc/fstab.gryonixnexus > /etc/fstab
rm -f /etc/fstab.gryonixnexus
WIPE=('/dev/sdg' '/dev/sdh')
for disk in "${WIPE[@]}"; do
  wipefs -a -q "$disk" || true
done
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
