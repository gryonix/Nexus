#!/bin/bash
set -uo pipefail
F='/var/tmp'/.gryonixnexus-speedtest.$$
trap 'rm -f "$F"' EXIT
if w=$(LC_ALL=C dd bs=1M if=/dev/zero of="$F" count=256 oflag=direct conv=fdatasync 2>&1); then
  r=$(LC_ALL=C dd bs=1M if="$F" of=/dev/null iflag=direct 2>&1); mode=direct
else
  w=$(LC_ALL=C dd bs=1M if=/dev/zero of="$F" count=256 conv=fdatasync 2>&1)
  r=$(LC_ALL=C dd bs=1M if="$F" of=/dev/null 2>&1); mode=cached
fi
echo "write $(printf '%s' "$w" | tail -n 1)"
echo "read $(printf '%s' "$r" | tail -n 1)"
echo "mode $mode"
echo GRYONIXNEXUS_SPEED_DONE
