#!/bin/bash
set -euo pipefail
POOL='tank'
zpool scrub "$POOL"
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
