#!/bin/sh
set -eu

CHIP=0
STATUS_PIN=17

# Timing definition (ms)

# Must be: odd number of entries so final state ends LOW

# Starts HIGH (1), then alternates

TIMINGS="320 100 180 100 180 100 180"

# Build comma-separated list for gpioset v2

build_toggle_string() {
  TOGGLE=""
  for t in $TIMINGS; do
    if [ -z "$TOGGLE" ]; then
      TOGGLE="${t}ms"
    else
      TOGGLE="${TOGGLE},${t}ms"
    fi
  done
  # Append ,0 so gpioset exits after sequence
  TOGGLE="${TOGGLE},0"
}

# libgpiod v2 (fast path)
pulse_v2() {
  build_toggle_string
  exec /usr/bin/gpioset -c "$CHIP" 
  --toggle "$TOGGLE" 
  "$STATUS_PIN=1"
}

# libgpiod v1 fallback
set_line() {
  /usr/bin/gpioset -c "$CHIP" "$STATUS_PIN=$1"
}

sleep_ms() {
  sleep "$(awk "BEGIN { printf "%.3f", $1/1000 }")"
}

pulse_v1() {
  state=1
  for t in $TIMINGS; do
    set_line "$state"
    sleep_ms "$t"
    if [ "$state" -eq 1 ]; then
      state=0
    else
      state=1
    fi
  done
  # ensure final LOW
  set_line 0
}

# Detect v2 support
if /usr/bin/gpioset --help 2>&1 | grep -q -- '--toggle'; then
  pulse_v2
else
  pulse_v1
fi

exit 0

