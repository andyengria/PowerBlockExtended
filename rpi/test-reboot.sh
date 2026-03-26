#!/usr/bin/env bash
set -e

CHIP=0
STATUS_PIN=17

/usr/bin/gpioset -c "$CHIP" \
  -t 200ms,500ms,300ms,300ms,300ms,300ms,300ms,300ms,300ms,300ms,0 \
  "$STATUS_PIN=1"

sleep 0.3
exec systemctl reboot
