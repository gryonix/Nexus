#!/bin/bash
set -euo pipefail
FAST='/mnt/fast/gryonixnexus-fast'
install -d "$FAST"
if ! command -v rsync >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -qq rsync >/dev/null
fi
move_dir() {
  local target="$1" source="$FAST/binds$1" old="$1.before-cache"
  if mountpoint -q "$target"; then echo "$target is already on the fast disk"; return 0; fi
  if [ ! -d "$target" ]; then echo "$target does not exist, skipped"; return 0; fi
  echo "Moving $target"
  install -d "$source" || return 1
  rsync -aHAX --delete "$target/" "$source/" || return 1
  if [ -e "$old" ]; then old="$old.$(date +%s)"; fi
  mv "$target" "$old" || return 1
  install -d "$target" || return 1
  grep -qF " $target none bind" /etc/fstab || echo "$source $target none bind,nofail,x-systemd.requires-mounts-for=$FAST 0 0" >> /etc/fstab || return 1
  mount "$target" || return 1
}
move_project() {
  local project="$1" rc=0 todo=0
  shift
  for dir in "$@"; do mountpoint -q "$dir" || todo=1; done
  if [ "$todo" = 0 ]; then echo "$project is already on the fast disk"; return 0; fi
  (cd "$project" && docker compose stop) || return 1
  for dir in "$@"; do move_dir "$dir" || rc=1; done
  (cd "$project" && docker compose start) || rc=1
  return $rc
}
move_project '/opt/immich' '/opt/immich/postgres' || FAILED=1
move_project '/opt/nextcloud' '/opt/nextcloud/db' '/opt/nextcloud/redis' || FAILED=1
[ "${FAILED:-0}" = 0 ] || exit 4
echo GRYONIXNEXUS_FAST_MOVE_DONE
