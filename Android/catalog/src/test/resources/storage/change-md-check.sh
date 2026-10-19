#!/bin/bash
set -euo pipefail
ARRAY='/dev/md127'
md="$(basename "$(readlink -f "$ARRAY")")"
echo check > "/sys/block/$md/md/sync_action"
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
