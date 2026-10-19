#!/bin/bash
set -euo pipefail
FILE=/swapfile-gryonixnexus
SIZE_MB=2048
if swapon --show=NAME --noheadings | grep -qx "$FILE"; then swapoff "$FILE"; fi
rm -f "$FILE"
FREE_MB=$(( $(df -B1 --output=avail / | tail -n 1 | tr -d ' ') / 1048576 ))
if [ "$SIZE_MB" -ge "$FREE_MB" ]; then echo "not enough disk: $((FREE_MB / 1024)) GB free" >&2; exit 3; fi
fallocate -l "${SIZE_MB}M" "$FILE" 2>/dev/null || dd if=/dev/zero of="$FILE" bs=1M count="$SIZE_MB" status=none
chmod 600 "$FILE"
mkswap "$FILE" >/dev/null
swapon "$FILE"
grep -q "^$FILE " /etc/fstab || echo "$FILE none swap sw 0 0" >> /etc/fstab
echo GRYONIXNEXUS_SWAP_DONE
