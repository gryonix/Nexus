#!/bin/bash
set -euo pipefail
ARRAY='/dev/md/gryonixnexus'
MOUNT='/srv/gryonixnexus-storage'
if ! command -v mdadm >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -q mdadm
fi
if ! mdadm --detail "$ARRAY" >/dev/null 2>&1; then
  mdadm --assemble "$ARRAY" --uuid='dd96909c:ae315ffe:3a59f52c:051376ba' --run
fi
install -d /etc/mdadm
grep -q 'dd96909c:ae315ffe:3a59f52c:051376ba' /etc/mdadm/mdadm.conf 2>/dev/null || mdadm --detail --brief "$ARRAY" >> /etc/mdadm/mdadm.conf
update-initramfs -u >/dev/null 2>&1 || true
if [ -z "$(blkid -s TYPE -o value "$ARRAY" || true)" ]; then
  echo "The array holds no filesystem; nothing was formatted."
  exit 3
fi
install -d "$MOUNT"
uuid="$(blkid -s UUID -o value "$ARRAY")"
grep -q "UUID=$uuid $MOUNT " /etc/fstab || echo "UUID=$uuid $MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
mountpoint -q "$MOUNT" || mount "$MOUNT"
echo GRYONIXNEXUS_RAID_IMPORT_DONE
