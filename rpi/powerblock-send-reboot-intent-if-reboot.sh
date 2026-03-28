#!/bin/sh
set -eu

CHIP=0
STATUS_PIN=17

# Single source of truth for timings in ms
#TIMINGS="500 80 300 80 300 80 300" # 1640 MS
#TIMINGS="320 100 180 100 180 100 180" # 1160 MS
TIMINGS="220 70 90 70 90 70 90"

LINE_ARG="${STATUS_PIN}=1"
LOGGER_TAG="powerblock-reboot-intent"

log() {
    logger -t "$LOGGER_TAG" "$1" || true
}

build_toggle_string() {
    TOGGLE=""
    for t in $TIMINGS; do
        if [ -z "$TOGGLE" ]; then
            TOGGLE="${t}ms"
        else
            TOGGLE="${TOGGLE},${t}ms"
        fi
    done
    TOGGLE="${TOGGLE},0"
}

sleep_ms() {
    sleep "$(awk "BEGIN { printf \"%.3f\", $1 / 1000 }")"
}

set_line_v1() {
    /usr/bin/gpioset -c "$CHIP" "${STATUS_PIN}=$1"
}

wait_for_powerblock_release() {
    # Wait up to ~2 seconds for the native daemon to really stop.
    i=0
    while [ "$i" -lt 100 ]; do
        if ! pgrep -f '/usr/bin/powerblockservice' >/dev/null 2>&1; then
            break
        fi
        sleep 0.02
        i=$((i + 1))
    done

    # Small extra settle delay after release.
    sleep 0.05
}

pulse_v2() {
    build_toggle_string
    exec /usr/bin/gpioset -c "$CHIP" \
        --toggle "$TOGGLE" \
        "$LINE_ARG"
}

pulse_v1() {
    state=1
    for t in $TIMINGS; do
        set_line_v1 "$state"
        sleep_ms "$t"
        if [ "$state" -eq 1 ]; then
            state=0
        else
            state=1
        fi
    done
    set_line_v1 0
}

log "entered"

wait_for_powerblock_release

log "sending pulse"

if /usr/bin/gpioset --help 2>&1 | grep -q -- '--toggle'; then
    pulse_v2
else
    pulse_v1
fi
