#!/bin/bash
set -euo pipefail
ARRAY='/dev/md127'
OLD='/dev/sdc'
if systemctl is-active -q gryonixnexus-disk-job; then
  echo "Another disk job is still running. Wait until it ends."
  exit 3
fi
CHECK=('/dev/sdb' '/dev/sdd' '/dev/sde')
if command -v smartctl >/dev/null 2>&1; then
  for disk in "${CHECK[@]}"; do
    if smartctl -H "$disk" 2>/dev/null | grep -q FAILED; then
      echo "$disk reports that it is failing. Replace that disk first."
      exit 3
    fi
  done
fi
if ! mdadm --detail "$ARRAY" | grep -qw -- "$OLD"; then
  echo "$OLD is not in this array."
  exit 3
fi
if mdadm --detail "$ARRAY" | grep -Eq 'State : .*(degraded|recovering|resyncing|reshaping)'; then
  echo "The array is not healthy right now. Wait until it is, then try again."
  exit 3
fi
if [ "$(blkid -s TYPE -o value "$ARRAY" || true)" != ext4 ]; then
  echo "Only an array with ext4 on it can give a disk back."
  exit 3
fi
room=$(( $(mdadm --detail "$ARRAY" | awk '/Used Dev Size :/ {print $5}') * 2 ))
MOUNT="$(findmnt -no TARGET "$ARRAY" | head -n 1 || true)"
if [ -n "$MOUNT" ] && [ "$(df -k --output=used "$MOUNT" | tail -n 1 | tr -d ' ')" -gt $((room * 9 / 10)) ]; then
  echo "The data does not fit on the disks that stay. Free some space first."
  exit 3
fi
cat > /var/lib/gryonixnexus-disk-job.sh <<'GNX_JOB'
#!/bin/bash
set -eEuo pipefail
exec >> /var/log/gryonixnexus-disk-job.log 2>&1
trap 'echo "GRYONIXNEXUS_DISK_JOB_FAILED $(date +%s)"' ERR
echo "GRYONIXNEXUS_DISK_JOB_START remove gryonixnexus $(date +%s)"
ARRAY='/dev/md127'
OLD='/dev/sdc'
room=$(( $(mdadm --detail "$ARRAY" | awk '/Used Dev Size :/ {print $5}') * 2 ))
MOUNT="$(findmnt -no TARGET "$ARRAY" | head -n 1 || true)"
stopped=""
restore() {
  if [ -n "$MOUNT" ] && ! mountpoint -q "$MOUNT"; then mount "$MOUNT" || true; fi
  if [ -n "$stopped" ]; then docker start $stopped >/dev/null || true; fi
}
trap restore EXIT
if [ -n "$MOUNT" ]; then
  if command -v docker >/dev/null 2>&1; then
    for c in $(docker ps -q); do
      if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$c" | grep -qF -- "$MOUNT"; then
        stopped="$stopped $c"
      fi
    done
    if [ -n "$stopped" ]; then docker stop $stopped >/dev/null; fi
  fi
  umount "$MOUNT"
fi
e2fsck -f -y "$ARRAY" || [ $? -le 1 ]
resize2fs "$ARRAY" "${room}K"
mdadm --grow "$ARRAY" --array-size="$room"
restore
mdadm --grow "$ARRAY" --raid-devices=3 --backup-file=/var/lib/gryonixnexus-md-reshape.backup
mdadm --wait "$ARRAY" || true
sleep 5
spare="$(mdadm --detail "$ARRAY" | awk '/spare/ && $NF ~ /^\/dev\// {print $NF}' | head -n 1)"
if [ -n "$spare" ] && [ "$spare" != "$OLD" ]; then
  mdadm "$ARRAY" --replace "$OLD" --with "$spare"
  mdadm --wait "$ARRAY" || true
  sleep 5
fi
mdadm "$ARRAY" --remove "$OLD"
mdadm --zero-superblock "$OLD" >/dev/null 2>&1 || true
rm -f /var/lib/gryonixnexus-md-reshape.backup
echo "GRYONIXNEXUS_DISK_JOB_DONE $(date +%s)"
GNX_JOB
: > /var/log/gryonixnexus-disk-job.log
chmod 644 /var/log/gryonixnexus-disk-job.log
systemctl reset-failed gryonixnexus-disk-job >/dev/null 2>&1 || true
systemd-run --quiet --collect --unit=gryonixnexus-disk-job /bin/bash /var/lib/gryonixnexus-disk-job.sh
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
