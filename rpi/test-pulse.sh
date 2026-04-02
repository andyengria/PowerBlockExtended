#!/usr/bin/env bash
set -euo pipefail

SERVICE="powerblockextended.service"
CONFIG_FILE="/etc/powerblockconfig.cfg"
PULSE_SECONDS="${1:-1}"
GPIOCHIP=0
STATUSPIN=17
BACKEND="sysfs"

log() {
    echo "[test-pulse] $*"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        local tmp
        tmp="$(awk -F= '
            /^\[powerblock\]/ { in_section=1; next }
            /^\[/ { in_section=0 }
            in_section && $1=="statuspin" {
                gsub(/[[:space:]]/, "", $2)
                print $2
                exit
            }
        ' "$CONFIG_FILE" 2>/dev/null || true)"
        [ -n "${tmp:-}" ] && STATUSPIN="$tmp"
    fi
}

detect_gpiochip() {
    local model_string
    model_string="$(grep -m1 'Model' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || true)"

    case "$model_string" in
        *"Pi 5"*|*"Compute Module 5"*)
            GPIOCHIP=4
            ;;
        *)
            GPIOCHIP=0
            ;;
    esac
}

detect_backend() {
    if ! command -v gpioset >/dev/null 2>&1; then
        BACKEND="sysfs"
        return
    fi

    local ver helptext
    ver="$(gpioset --version 2>/dev/null || true)"

    case "$ver" in
        *" v2."*|*" 2."*)
            BACKEND="gpiod-v2"
            return
            ;;
        *" v1."*|*" 1."*)
            BACKEND="gpiod-v1"
            return
            ;;
    esac

    helptext="$(gpioset --help 2>&1 || true)"

    if printf '%s\n' "$helptext" | grep -q -- '--hold-period'; then
        BACKEND="gpiod-v2"
    elif printf '%s\n' "$helptext" | grep -q -- '--toggle'; then
        BACKEND="gpiod-v2"
    elif printf '%s\n' "$helptext" | grep -q -- '--mode'; then
        BACKEND="gpiod-v1"
    else
        BACKEND="sysfs"
    fi
}

sysfs_export_if_needed() {
    local pin="$1"
    if [ ! -d "/sys/class/gpio/gpio$pin" ]; then
        echo "$pin" > /sys/class/gpio/export
        sleep 0.1
    fi
}

pulse_sysfs() {
    sysfs_export_if_needed "$STATUSPIN"
    echo out > "/sys/class/gpio/gpio$STATUSPIN/direction"
    echo 0 > "/sys/class/gpio/gpio$STATUSPIN/value"
    sleep "$PULSE_SECONDS"
    echo 1 > "/sys/class/gpio/gpio$STATUSPIN/value"
}

pulse_gpiod_v1() {
    gpioset -c "$GPIOCHIP" -m=time -s "$PULSE_SECONDS" "$STATUSPIN=0"
    gpioset -c "$GPIOCHIP" -m=time -s 0.05 "$STATUSPIN=1"
}

pulse_gpiod_v2() {
    local ms
    ms="$(awk "BEGIN { printf \"%d\", $PULSE_SECONDS * 1000 }")"
    gpioset -c "$GPIOCHIP" -t "${ms}ms,50ms,0" "$STATUSPIN=0"
}

main() {
    [ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

    load_config
    detect_gpiochip
    detect_backend

    log "stopping service"
    systemctl stop "$SERVICE"
    sleep 0.5

    log "remaining processes:"
    pgrep -af powerblockextended || true

    log "backend=$BACKEND gpiochip=$GPIOCHIP statuspin=$STATUSPIN pulse=${PULSE_SECONDS}s"

    case "$BACKEND" in
        sysfs) pulse_sysfs ;;
        gpiod-v1) pulse_gpiod_v1 ;;
        gpiod-v2) pulse_gpiod_v2 ;;
        *) echo "unknown backend: $BACKEND"; exit 1 ;;
    esac

    log "starting service"
    systemctl start "$SERVICE"
    sleep 0.5

    log "running processes:"
    pgrep -af powerblockextended || true
}

main "$@"
