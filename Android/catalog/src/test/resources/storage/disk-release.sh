#!/bin/bash
set -euo pipefail
MOUNT='/srv/disk-sdi'
if [ -n "$MOUNT" ] && command -v docker >/dev/null 2>&1; then
  for c in $(docker ps -aq); do
    if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$c" | grep -qF -- "$MOUNT"; then
      echo "Services keep their data here. Move or remove them first."
      exit 3
    fi
  done
fi
if mountpoint -q "$MOUNT"; then
  umount "$MOUNT"
fi
awk -v m="$MOUNT" '$2 != m' /etc/fstab > /etc/fstab.gryonixnexus
cat /etc/fstab.gryonixnexus > /etc/fstab
rm -f /etc/fstab.gryonixnexus
echo GRYONIXNEXUS_DISK_RELEASE_DONE
