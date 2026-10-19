#!/bin/bash
set -euo pipefail
ARRAY='/dev/md127'
MOUNT="$(findmnt -no TARGET "$ARRAY" | head -n 1 || true)"
if [ -n "$MOUNT" ] && command -v docker >/dev/null 2>&1; then
  for c in $(docker ps -aq); do
    if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$c" | grep -qF -- "$MOUNT"; then
      echo "Services keep their data here. Move or remove them first."
      exit 3
    fi
  done
fi
uuid="$(mdadm --detail "$ARRAY" | awk '/UUID :/ {print $3}')"
members="$(mdadm --detail "$ARRAY" | awk '$NF ~ /^\/dev\// && NF > 4 {print $NF}')"
if [ -n "$MOUNT" ]; then
  umount "$MOUNT"
  awk -v m="$MOUNT" '$2 != m' /etc/fstab > /etc/fstab.gryonixnexus
  cat /etc/fstab.gryonixnexus > /etc/fstab
  rm -f /etc/fstab.gryonixnexus
fi
mdadm --stop "$ARRAY"
for disk in $members; do
  mdadm --zero-superblock "$disk" || true
  wipefs -a -q "$disk" || true
done
if [ -f /etc/mdadm/mdadm.conf ]; then
  sed -i "/UUID=$uuid/d" /etc/mdadm/mdadm.conf
fi
update-initramfs -u >/dev/null 2>&1 || true
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
