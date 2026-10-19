#!/bin/bash
set -euo pipefail
MOUNT='/srv/data'
if ! mountpoint -q "$MOUNT"; then
  echo "$MOUNT is not mounted."
  exit 3
fi
btrfs scrub start "$MOUNT" >/dev/null
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
