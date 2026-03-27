#!/bin/sh
set -eu

CHIP="gpiochip0"
STATUS_PIN="17"
GAP_MS="80"

is_reboot_transaction() {
    systemctl list-jobs --no-pager 2>/dev/null | grep -q 'reboot.target.*start'
}

have_gpioset_toggle() {
    /usr/bin/gpioset --help 2>&1 | grep -q -- '--toggle'
}

pulse_v2() {
    exec /usr/bin/gpioset "$CHIP" "$STATUS_PIN=1" \
        --toggle 500ms,"${GAP_MS}"ms,300ms,"${GAP_MS}"ms,300ms,"${GAP_MS}"ms,300ms,"${GAP_MS}"ms,300ms,0
}

set_for_ms_v1() {
    value="$1"
    duration_ms="$2"

    sec=$((duration_ms / 1000))
    usec=$(((duration_ms % 1000) * 1000))

    /usr/bin/gpioset --mode=time --sec="$sec" --usec="$usec" \
        "$CHIP" "${STATUS_PIN}=${value}"
}

pulse_v1() {
    set_for_ms_v1 1 500
    set_for_ms_v1 0 "$GAP_MS"

    set_for_ms_v1 1 300
    set_for_ms_v1 0 "$GAP_MS"

    set_for_ms_v1 1 300
    set_for_ms_v1 0 "$GAP_MS"

    set_for_ms_v1 1 300
    set_for_ms_v1 0 "$GAP_MS"

    set_for_ms_v1 1 300
    set_for_ms_v1 0 "$GAP_MS"
}

is_reboot_transaction || exit 0

if have_gpioset_toggle; then
    pulse_v2
else
    pulse_v1
fi
