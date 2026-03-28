#!/bin/sh
set -eu

CHIP=0
STATUS_PIN=17
#TIMINGS="320 100 180 100 180 100 180" # 1160 MS
TIMINGS="220 70 90 70 90 70 90"
LINE_ARG="${STATUS_PIN}=1"

[ -f /run/powerblock-reboot-intent ] || exit 0
rm -f /run/powerblock-reboot-intent

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

pulse_v2() {
    build_toggle_string
    /usr/bin/gpioset -c "$CHIP" \
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

if /usr/bin/gpioset --help 2>&1 | grep -q -- '--toggle'; then
    pulse_v2
else
    pulse_v1
fi

exit 0
