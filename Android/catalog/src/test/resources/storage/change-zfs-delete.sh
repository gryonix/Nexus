#!/bin/bash
set -euo pipefail
POOL='tank'
MOUNT="$(zfs get -H -o value mountpoint "$POOL" 2>/dev/null | grep '^/' || true)"
if [ -n "$MOUNT" ] && command -v docker >/dev/null 2>&1; then
  for c in $(docker ps -aq); do
    if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$c" | grep -qF -- "$MOUNT"; then
      echo "Services keep their data here. Move or remove them first."
      exit 3
    fi
  done
fi
REAL="$(zpool status -LP "$POOL" | awk '$1 ~ /^\/dev\// {print $1}')"
for disk in '/dev/sde1' '/dev/sdf1'; do
  if ! printf '%s\n' "$REAL" | grep -qxF -- "$disk"; then
    echo "$disk is not in this pool."
    exit 3
  fi
done
zpool destroy -f "$POOL"
WIPE=('/dev/sde1' '/dev/sdf1')
for disk in "${WIPE[@]}"; do
  zpool labelclear -f "$disk" >/dev/null 2>&1 || true; wipefs -a -q "$disk" || true
done
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
