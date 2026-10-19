#!/bin/bash
set -euo pipefail
MOUNT='/srv/data'
OLD='/dev/sdh'
NEW='/dev/sdi'
gnx_expect() {
  case "$1" in
    '/dev/sdi') echo '4000787030016|WD-WCC4E1FREE1' ;;
  esac
}
gnx_free() {
  if [ ! -b "$1" ]; then
    echo "$1 is not a disk on this server."
    exit 3
  fi
  local want size serial
  want="$(gnx_expect "$1")"
  if [ -n "$want" ]; then
    size="$(lsblk -dnbo SIZE "$1" | tr -d '[:space:]')"
    serial="$(lsblk -dno SERIAL "$1" | tr -d '[:space:]')"
    if [ "${want%%|*}" != "$size" ] || { [ -n "${want#*|}" ] && [ -n "$serial" ] && [ "${want#*|}" != "$serial" ]; }; then
      echo "$1 is not the disk the app listed. Nothing was erased."
      exit 3
    fi
  fi
  if [ -n "$(lsblk -rno MOUNTPOINT "$1" | tr -d '[:space:]')" ] || lsblk -rno TYPE "$1" | grep -E '^(raid|lvm|crypt)' >/dev/null; then
    echo "$1 is in use. Nothing was erased."
    exit 3
  fi
}
if systemctl is-active -q gryonixnexus-disk-job; then
  echo "Another disk job is still running. Wait until it ends."
  exit 3
fi
CHECK=('/dev/sdg')
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
gnx_free "$NEW"
wipefs -a -q "$NEW"
cat > /var/lib/gryonixnexus-disk-job.sh <<'GNX_JOB'
#!/bin/bash
set -eEuo pipefail
exec >> /var/log/gryonixnexus-disk-job.log 2>&1
trap 'echo "GRYONIXNEXUS_DISK_JOB_FAILED $(date +%s)"' ERR
echo "GRYONIXNEXUS_DISK_JOB_START replace data $(date +%s)"
MOUNT='/srv/data'
OLD='/dev/sdh'
NEW='/dev/sdi'
btrfs replace start -B -f "$OLD" "$NEW" "$MOUNT"
devid="$(btrfs filesystem show "$MOUNT" | awk -v d="$NEW" '$NF == d {print $2}')"
btrfs filesystem resize "$devid:max" "$MOUNT"
echo "GRYONIXNEXUS_DISK_JOB_DONE $(date +%s)"
GNX_JOB
: > /var/log/gryonixnexus-disk-job.log
chmod 644 /var/log/gryonixnexus-disk-job.log
systemctl reset-failed gryonixnexus-disk-job >/dev/null 2>&1 || true
systemd-run --quiet --collect --unit=gryonixnexus-disk-job /bin/bash /var/lib/gryonixnexus-disk-job.sh
echo GRYONIXNEXUS_ARRAY_CHANGE_DONE
