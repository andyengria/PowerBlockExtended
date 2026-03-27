#!/bin/sh
set -eu

CHIP=gpiochip0
STATUS_PIN=17

# Only act on real reboot transactions.
if ! systemctl list-jobs --no-pager 2>/dev/null | grep -q 'reboot.target.*start'; then
    exit 0
fi

exec /usr/bin/gpioset "$CHIP" "$STATUS_PIN=1" \
  --toggle 500ms,300ms,300ms,300ms,300ms,300ms,300ms,300ms,0
