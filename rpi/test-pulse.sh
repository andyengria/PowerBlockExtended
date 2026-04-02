#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/powerblockconfig.cfg"
HOLD_BIN="/usr/local/sbin/powerblockextended-hold"

log() {
    echo "[test-pulse] $*"
}

fail() {
    echo "[test-pulse] ERROR: $*" >&2
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "run as root: sudo bash test-pulse.sh"
    fi
}

load_config() {
    GPIOCHIP="0"
    STATUSPIN="17"
    HOLD_LEVEL="1"
    PULSE_SECONDS="${1:-1}"

    if [ -f "$CONFIG_FILE" ]; then
        STATUSPIN="$(awk -F= '
            /^\[powerblock\]/ { in_section=1; next }
            /^\[/ && $0 !~ /^\[powerblock\]/ { in_section=0 }
            in_section && $1=="statuspin" { gsub(/[ \t\r]/,"",$2); print $2; exit }
        ' "$CONFIG_FILE")"

        if [ -z "${STATUSPIN:-}" ]; then
            STATUSPIN="17"
        fi
    fi
}

detect_backend() {
    if command -v gpiodetect >/dev/null 2>&1 \
        && command -v gpioset >/dev/null 2>&1 \
        && command -v gpioget >/dev/null 2>&1; then

        local ver major
        ver="$(gpioset --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
        major="$(echo "${ver:-0}" | cut -d. -f1)"

        if [ "${major:-0}" -ge 2 ] 2>/dev/null; then
            BACKEND="gpiod-v2"
        else
            BACKEND="gpiod-v1"
        fi
    else
        BACKEND="sysfs"
    fi
}

find_hold_pid() {
    HOLD_PID="$(pgrep -f "^bash ${HOLD_BIN} " || true)"
}

stop_hold() {
    find_hold_pid
    if [ -n "${HOLD_PID:-}" ]; then
        log "stopping hold helper pid=${HOLD_PID}"
        kill "${HOLD_PID}" || true
        sleep 0.2
    else
        log "no existing hold helper found"
    fi
}

sysfs_export_if_needed() {
    local pin="$1"
    [ -d "/sys/class/gpio/gpio${pin}" ] || echo "$pin" > /sys/class/gpio/export
}

sysfs_set_direction_output() {
    local pin="$1"
    sysfs_export_if_needed "$pin"
    echo out > "/sys/class/gpio/gpio${pin}/direction"
}

sysfs_write() {
    local pin="$1"
    local level="$2"
    echo "$level" > "/sys/class/gpio/gpio${pin}/value"
}

send_pulse() {
    local active_level inactive_level
    active_level="${HOLD_LEVEL}"
    if [ "$active_level" = "1" ]; then
        inactive_level="0"
    else
        inactive_level="1"
    fi

    log "sending pulse: backend=${BACKEND} gpiochip=${GPIOCHIP} pin=${STATUSPIN} active=${active_level} duration=${PULSE_SECONDS}s"

    case "$BACKEND" in
        sysfs)
            sysfs_set_direction_output "$STATUSPIN"
            sysfs_write "$STATUSPIN" "$active_level"
            sleep "$PULSE_SECONDS"
            sysfs_write "$STATUSPIN" "$inactive_level"
            ;;
        gpiod-v1)
            gpioset "$GPIOCHIP" "${STATUSPIN}=${active_level}" &
            local pid=$!
            sleep "$PULSE_SECONDS"
            kill "$pid" || true
            wait "$pid" 2>/dev/null || true
            ;;
        gpiod-v2)
            gpioset --mode=signal --sec="$PULSE_SECONDS" "$GPIOCHIP" "${STATUSPIN}=${active_level}"
            ;;
        *)
            fail "unknown backend: $BACKEND"
            ;;
    esac
}

restart_hold() {
    log "restarting hold helper: ${HOLD_BIN} ${BACKEND} ${GPIOCHIP} ${STATUSPIN} ${HOLD_LEVEL}"
    nohup bash "$HOLD_BIN" "$BACKEND" "$GPIOCHIP" "$STATUSPIN" "$HOLD_LEVEL" >/tmp/powerblock-test-pulse.log 2>&1 &
    sleep 0.2
    pgrep -af "$HOLD_BIN" || true
}

main() {
    require_root
    load_config "${1:-1}"
    detect_backend

    log "config: gpiochip=${GPIOCHIP} statuspin=${STATUSPIN} holdlevel=${HOLD_LEVEL}"
    stop_hold
    send_pulse
    restart_hold
    log "done"
}

main "$@"
