#!/bin/bash
set -euo pipefail
for old in '/opt/immich/postgres.before-cache' '/opt/immich/postgres.before-cache'.*; do [ -d "$old" ] || continue; rm -rf -- "$old"; echo "removed $old"; done
echo GRYONIXNEXUS_FAST_CLEANUP_DONE
