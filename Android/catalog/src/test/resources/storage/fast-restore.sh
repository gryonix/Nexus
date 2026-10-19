#!/bin/bash
set -euo pipefail
if ! command -v rsync >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -qq rsync >/dev/null
fi
bound_source() {
  awk -v t="$1" '$2 == t && $3 == "none" {print $1; exit}' /etc/fstab
}
restore_dir() {
  local target="$1" source
  source="$(bound_source "$target")"
  if [ -z "$source" ]; then echo "$target is not on the fast disk"; return 0; fi
  echo "Bringing back $target"
  if mountpoint -q "$target"; then umount "$target" || return 1; fi
  rsync -aHAX --delete "$source/" "$target/" || return 1
  awk -v t="$target" '!($2 == t && $3 == "none")' /etc/fstab > /etc/fstab.gryonixnexus || return 1
  cat /etc/fstab.gryonixnexus > /etc/fstab && rm -f /etc/fstab.gryonixnexus || return 1
}
restore_project() {
  local project="$1" rc=0 todo=0
  shift
  for dir in "$@"; do [ -n "$(bound_source "$dir")" ] && todo=1; done
  if [ "$todo" = 0 ]; then echo "$project is on the system disk"; return 0; fi
  (cd "$project" && docker compose stop) || return 1
  for dir in "$@"; do restore_dir "$dir" || rc=1; done
  (cd "$project" && docker compose start) || rc=1
  return $rc
}
restore_project '/opt/immich' '/opt/immich/postgres' || FAILED=1
restore_project '/opt/nextcloud' '/opt/nextcloud/db' '/opt/nextcloud/redis' || FAILED=1
[ "${FAILED:-0}" = 0 ] || exit 4
echo GRYONIXNEXUS_FAST_RESTORE_DONE
