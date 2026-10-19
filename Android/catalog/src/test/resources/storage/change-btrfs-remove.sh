#!/bin/bash
set -euo pipefail
MOUNT='/srv/data'
OLD='/dev/sdh'
if systemctl is-active -q gryonixnexus-disk-job; then
  echo "Another disk job is still running. Wait until it ends."
  exit 3
fi
CHECK=('/dev/sdg' '/dev/sdi')
if command -v smartctl >/dev/null 2>&1; then
  for disk in "${CHECK[@]}"; do
    if smartctl -H "$disk" 2>/dev/null | grep -q FAILED; then
      echo "$disk reports that it is failing. Replace that disk first."
      exit 3
    fi
  done
fi
if ! mountpoint -q "$MOUNT"; then
  echo "$MOUNT is not mounted."
  exit 3
fi
if ! btrfs filesystem show "$MOUNT" | grep -qw -- "$OLD"; then
  echo "$OLD is not in this filesystem."
  exit 3
fi
cat > /var/lib/gryonixnexus-disk-job.sh <<'GNX_JOB'
#!/bin/bash
set -eEuo pipefail
exec >> /var/log/gryonixnexus-disk-job.log 2>&1
trap 'echo "GRYONIXNEXUS_DISK_JOB_FAILED $(date +%s)"' ERR
echo "GRYONIXNEXUS_DISK_JOB_START remove data $(date +%s)"
MOUNT='/srv/data'
OLD='/dev/sdh'
btrfs device remove "$OLD" "$MOUNT"
wipefs -a -q "$OLD" || true
echo "GRYONIXNEXUS_DISK_JOB_DONE $(date +%s)"
GNX_JOB
: > /var/log/gryonixnexus-disk-job.log
chmod 644 /var/log/gryonixnexus-disk-job.log
systemctl reset-failed gryonixnexus-disk-job >/dev/null 2>&1 || true
systemd-run --quiet --collect --unit=gryonixnexus-disk-job /bin/bash /var/lib/gryonixnexus-disk-job.sh
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
