#!/bin/bash
set -uo pipefail
DISK='/dev/sdi'
if command -v ledctl >/dev/null 2>&1; then
  ledctl locate="$DISK" >/dev/null 2>&1 || true
fi
timeout 30 dd if="$DISK" of=/dev/null bs=1M iflag=direct status=none || true
if command -v ledctl >/dev/null 2>&1; then
  ledctl locate_off="$DISK" >/dev/null 2>&1 || true
fi
echo GRYONIXNEXUS_DISK_BLINK_DONE
