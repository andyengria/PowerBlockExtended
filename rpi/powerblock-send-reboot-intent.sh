#!/bin/sh
set -e

CHIP=0
STATUS_PIN=17

# Only send the pulse if this shutdown transaction is actually a reboot.
if ! systemctl list-jobs --no-pager | grep -q 'reboot.target.*start'; then
  exit 0
fi

pkill -f /usr/bin/powerblockservice >/dev/null 2>&1 || true
pkill gpioset >/dev/null 2>&1 || true

/usr/bin/gpioset -c "$CHIP" \
  -t 200ms,500ms,300ms,300ms,300ms,300ms,300ms,300ms,300ms,300ms,0 \
  "$STATUS_PIN=1"

/bin/sleep 0.3
exit 0
