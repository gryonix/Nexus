#!/bin/bash
set -euo pipefail
POOL='tank'
OLD='/dev/sdf1'
if systemctl is-active -q gryonixnexus-disk-job; then
  echo "Another disk job is still running. Wait until it ends."
  exit 3
fi
CHECK=('/dev/sde')
if command -v smartctl >/dev/null 2>&1; then
  for disk in "${CHECK[@]}"; do
    if smartctl -H "$disk" 2>/dev/null | grep -q FAILED; then
      echo "$disk reports that it is failing. Replace that disk first."
      exit 3
    fi
  done
fi
if ! zpool status -x "$POOL" | grep -q 'is healthy'; then
  echo "The pool is not healthy right now. Wait until it is, then try again."
  exit 3
fi
zpool remove "$POOL" "$OLD"
cat > /var/lib/gryonixnexus-disk-job.sh <<'GNX_JOB'
#!/bin/bash
set -eEuo pipefail
exec >> /var/log/gryonixnexus-disk-job.log 2>&1
trap 'echo "GRYONIXNEXUS_DISK_JOB_FAILED $(date +%s)"' ERR
echo "GRYONIXNEXUS_DISK_JOB_START remove tank $(date +%s)"
POOL='tank'
OLD='/dev/sdf1'
zpool wait -t remove "$POOL"
zpool labelclear -f "$OLD" >/dev/null 2>&1 || true
echo "GRYONIXNEXUS_DISK_JOB_DONE $(date +%s)"
GNX_JOB
: > /var/log/gryonixnexus-disk-job.log
chmod 644 /var/log/gryonixnexus-disk-job.log
systemctl reset-failed gryonixnexus-disk-job >/dev/null 2>&1 || true
systemd-run --quiet --collect --unit=gryonixnexus-disk-job /bin/bash /var/lib/gryonixnexus-disk-job.sh
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
