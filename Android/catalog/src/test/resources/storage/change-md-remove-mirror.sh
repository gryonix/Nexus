#!/bin/bash
set -euo pipefail
ARRAY='/dev/md127'
OLD='/dev/sdc'
if mdadm --detail "$ARRAY" | grep -Eq 'State : .*(degraded|recovering|resyncing|reshaping)'; then
  echo "The array is not healthy right now. Wait until it is, then try again."
  exit 3
fi
if mdadm --detail "$ARRAY" | grep -qw -- "$OLD"; then
  mdadm "$ARRAY" --fail "$OLD"
  mdadm "$ARRAY" --remove "$OLD"
fi
if [ "$(mdadm --detail "$ARRAY" | awk '/Raid Devices :/ {print $4}')" -gt 1 ]; then
  mdadm --grow "$ARRAY" --raid-devices=1 --force
fi
mdadm --zero-superblock "$OLD" >/dev/null 2>&1 || true
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
