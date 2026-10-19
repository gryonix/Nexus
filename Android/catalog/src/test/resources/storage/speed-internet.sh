#!/bin/bash
set -uo pipefail
command -v curl >/dev/null 2>&1 || { echo nocurl; exit 0; }
echo "down $(curl -s -o /dev/null -w '%{speed_download} %{http_code}' --max-time 20 'https://speed.cloudflare.com/__down?bytes=50000000'; true)"
echo "up $(head -c 25000000 /dev/zero | curl -s -o /dev/null -w '%{speed_upload} %{http_code}' --max-time 20 --data-binary @- 'https://speed.cloudflare.com/__up'; true)"
echo "ping $(curl -s -o /dev/null -w '%{time_connect}' --max-time 10 'https://speed.cloudflare.com/__down?bytes=0'; true)"
echo GRYONIXNEXUS_SPEED_DONE
