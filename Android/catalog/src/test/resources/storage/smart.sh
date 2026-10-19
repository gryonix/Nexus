#!/bin/bash
set -uo pipefail
if ! command -v smartctl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y -qq --no-install-recommends smartmontools >/dev/null 2>&1 \
    || { echo "smartmontools could not be installed"; exit 3; }
fi
echo "### "'/dev/sda'; smartctl --json=c -H -A -i '/dev/sda'; echo
echo "### "'/dev/sdb'; smartctl --json=c -H -A -i '/dev/sdb'; echo
echo GRYONIXNEXUS_SMART_DONE
