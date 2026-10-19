#!/bin/bash
set -euo pipefail
FAST='/srv/gryonixnexus-fast'
DISK='/dev/nvme0n1'
if ! mountpoint -q "$FAST"; then
  if [ -z "$(lsblk -nro FSTYPE "$DISK" | tr -d '[:space:]')" ] && [ "$(lsblk -nro NAME "$DISK" | wc -l)" -eq 1 ]; then
    mkfs.ext4 -q -L gnx-fast "$DISK"
  fi
  install -d "$FAST"
  uuid="$(blkid -s UUID -o value "$DISK")"
  grep -q "UUID=$uuid $FAST " /etc/fstab || echo "UUID=$uuid $FAST ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
  mount "$FAST"
fi
if ! command -v docker >/dev/null 2>&1 && [ ! -s /etc/docker/daemon.json ]; then
  install -d /etc/docker "$FAST/docker"
  printf '{\n  "data-root": "%s/docker"\n}\n' "$FAST" > /etc/docker/daemon.json
fi
bind_fast() {
  local target="$1" source="$FAST/binds$1"
  install -d "$source" "$target"
  mountpoint -q "$target" && return 0
  if [ -n "$(ls -A "$target")" ]; then
    echo "$target already holds data, left in place"
    return 0
  fi
  grep -qF " $target none bind" /etc/fstab || echo "$source $target none bind,nofail,x-systemd.requires-mounts-for=$FAST 0 0" >> /etc/fstab
  mount "$target"
}
bind_fast '/opt/immich/postgres'
bind_fast '/opt/nextcloud/db'
echo GRYONIXNEXUS_STORAGE_DONE
