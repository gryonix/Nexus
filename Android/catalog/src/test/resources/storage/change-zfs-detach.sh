#!/bin/bash
set -euo pipefail
POOL='tank'
OLD='/dev/sdf1'
if ! zpool status -x "$POOL" | grep -q 'is healthy'; then
  echo "The pool is not healthy right now. Wait until it is, then try again."
  exit 3
fi
zpool offline "$POOL" "$OLD"
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
