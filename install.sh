#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"
REPO_BRANCH="${REPO_BRANCH:-main}"

SERVICE_NAME="powerblockextended.service"

LEGACY_SERVICE_NAME="powerblock.service"

BIN_MAIN_SRC="rpi/powerblockextended"
BIN_HOLD_SRC="rpi/powerblockextended-hold"
UNIT_MAIN_SRC="rpi/powerblockextended.service"

BIN_MAIN_DST="/usr/local/sbin/powerblockextended"
BIN_HOLD_DST="/usr/local/sbin/powerblockextended-hold"
UNIT_MAIN_DST="/etc/systemd/system/powerblockextended.service"

HOOK_DIR="/usr/lib/systemd/system-shutdown"
HOOK_DST="${HOOK_DIR}/powerblockextended-reboot-pulse"

CONFIG_DST="/etc/powerblockconfig.cfg"
SHUTDOWN_SCRIPT_DST="/etc/powerblockswitchoff.sh"

RUNTIME_DIR="/run/powerblockextended"

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo ./install.sh" >&2
    exit 1
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

bootstrap_if_needed() {
  local script_path script_dir

  script_path="$(readlink -f "$0" 2>/dev/null || true)"
  script_dir=""

  if [ -n "$script_path" ] && [ -f "$script_path" ]; then
    script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  fi

  if [ -n "$script_dir" ] &&
     [ -f "${script_dir}/${BIN_MAIN_SRC}" ] &&
     [ -f "${script_dir}/${BIN_HOLD_SRC}" ] &&
     [ -f "${script_dir}/${UNIT_MAIN_SRC}" ]; then
    return 0
  fi

  echo "Installer is not running from the repository root."
  echo "Bootstrapping repository into /tmp..."

  if ! have_cmd git; then
    echo "ERROR: git is required for bootstrap install." >&2
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d /tmp/powerblockextended.XXXXXX)"
  echo "Cloning ${REPO_URL} (branch: ${REPO_BRANCH}) to ${tmpdir}..."
  git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$tmpdir"
  echo "Re-running installer from cloned repository..."
  exec bash "${tmpdir}/install.sh" "$@"
}

repo_root() {
  local script_path
  script_path="$(readlink -f "$0")"
  cd "$(dirname "$script_path")"
  pwd
}

detect_status_pin() {
  local pin="17"

  if [ -f "$CONFIG_DST" ]; then
    local cfgpin
    cfgpin="$(awk -F= '
      $0 ~ /^\[powerblock\]/ { in_section=1; next }
      /^\[/ { in_section=0 }
      in_section && $1=="statuspin" {
        gsub(/[[:space:]]/, "", $2)
        print $2
        exit
      }
    ' "$CONFIG_DST" 2>/dev/null || true)"

    if [ -n "$cfgpin" ]; then
      pin="$cfgpin"
    fi
  fi

  echo "$pin"
}

detect_gpiochip() {
  local model_string
  model_string="$(grep -m1 'Model' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || true)"

  case "$model_string" in
    *"Pi 5"*|*"Compute Module 5"*)
      echo 4
      ;;
    *)
      echo 0
      ;;
  esac
}

detect_hook_backend() {
  if ! have_cmd gpioset; then
    echo "sysfs"
    return
  fi

  local ver helptext
  ver="$(gpioset --version 2>/dev/null || true)"

  case "$ver" in
    *" v2."*|*" 2."*)
      echo "gpiod-v2"
      return
      ;;
    *" v1."*|*" 1."*)
      echo "gpiod-v1"
      return
      ;;
  esac

  helptext="$(gpioset --help 2>&1 || true)"

  if printf '%s\n' "$helptext" | grep -q -- '--hold-period'; then
    echo "gpiod-v2"
    return
  fi

  if printf '%s\n' "$helptext" | grep -q -- '--toggle'; then
    echo "gpiod-v2"
    return
  fi

  if printf '%s\n' "$helptext" | grep -q -- '--mode'; then
    echo "gpiod-v1"
    return
  fi

  echo "sysfs"
}

install_main_binaries() {
  local root="$1"

  echo "Installing binaries..."
  install -D -m 0755 "${root}/${BIN_MAIN_SRC}" "$BIN_MAIN_DST"
  install -D -m 0755 "${root}/${BIN_HOLD_SRC}" "$BIN_HOLD_DST"
}

install_units() {
  local root="$1"

  echo "Installing systemd unit..."
  install -D -m 0644 "${root}/${UNIT_MAIN_SRC}" "$UNIT_MAIN_DST"
}

install_default_config_if_missing() {
  if [ -e "$CONFIG_DST" ]; then
    echo "Preserving existing config at $CONFIG_DST"
    return
  fi

  echo "Installing default config at $CONFIG_DST..."
  cat > "$CONFIG_DST" <<'EOF'
[powerblock]
activated=1
statuspin=17
shutdownpin=18
logging=1
shutdownscript=/etc/powerblockswitchoff.sh
EOF
  chmod 0644 "$CONFIG_DST"
}

install_shutdown_helper_if_missing() {
  if [ -e "$SHUTDOWN_SCRIPT_DST" ]; then
    echo "Preserving existing shutdown helper at $SHUTDOWN_SCRIPT_DST"
    return
  fi

  echo "Installing default shutdown helper at $SHUTDOWN_SCRIPT_DST..."
  cat > "$SHUTDOWN_SCRIPT_DST" <<'EOF'
#!/bin/bash
exec /sbin/shutdown -h now "PowerBlockExtended requested shutdown"
EOF
  chmod 0755 "$SHUTDOWN_SCRIPT_DST"
}

install_reboot_pulse_hook() {
  local status_pin="$1"
  local gpiochip="$2"
  local backend="$3"

  echo "Installing reboot pulse hook: backend=${backend}, gpiochip=${gpiochip}, statuspin=${status_pin}"
  mkdir -p "$HOOK_DIR"

  case "$backend" in
    gpiod-v2)
      cat > "$HOOK_DST" <<EOF
#!/bin/sh
ACTION="\${1:-}"

case "\$ACTION" in
  reboot|kexec) ;;
  *) exit 0 ;;
esac

/usr/bin/gpioset -c ${gpiochip} -t 250ms,50ms,0 ${status_pin}=0

exit 0
EOF
      ;;
        gpiod-v1)
      cat > "$HOOK_DST" <<EOF
#!/bin/sh
ACTION="\${1:-}"

case "\$ACTION" in
  reboot|kexec) ;;
  *) exit 0 ;;
esac

/usr/bin/gpioset -m time -s 0 -u 250000 ${gpiochip} ${status_pin}=0
/usr/bin/gpioset -m time -s 1 ${gpiochip} ${status_pin}=1

exit 0
EOF
      ;;
    sysfs)
      cat > "$HOOK_DST" <<EOF
#!/bin/sh
ACTION="\${1:-}"
GPIO_BASE="/sys/class/gpio"
GPIO_DIR="\${GPIO_BASE}/gpio${status_pin}"

case "\$ACTION" in
  reboot|kexec) ;;
  *) exit 0 ;;
esac

if [ ! -d "\$GPIO_DIR" ]; then
  echo "${status_pin}" > "\$GPIO_BASE/export" 2>/dev/null || exit 0
  /usr/bin/sleep 0.1
fi

echo out > "\$GPIO_DIR/direction" 2>/dev/null || exit 0
echo 0 > "\$GPIO_DIR/value" 2>/dev/null || exit 0
/usr/bin/sleep 0.25
echo 1 > "\$GPIO_DIR/value" 2>/dev/null || exit 0
/usr/bin/sleep 0.05

exit 0
EOF
      ;;
    *)
      echo "ERROR: unsupported reboot hook backend: ${backend}" >&2
      exit 1
      ;;
  esac

  chmod 0755 "$HOOK_DST"
}

disable_legacy_service() {
  if systemctl list-unit-files | grep -q "^${LEGACY_SERVICE_NAME}"; then
    echo "Disabling and masking legacy ${LEGACY_SERVICE_NAME}..."
    systemctl disable --now "$LEGACY_SERVICE_NAME" 2>/dev/null || true
    systemctl mask "$LEGACY_SERVICE_NAME" 2>/dev/null || true
  fi
}

cleanup_obsolete_pulse_unit() {
  local pulse_unit="/etc/systemd/system/powerblockextended-pulse.service"

  if [ -f "$pulse_unit" ]; then
    echo "Removing obsolete pulse helper unit..."
    systemctl disable --now powerblockextended-pulse.service 2>/dev/null || true
    rm -f "$pulse_unit"
  fi
}

enable_and_start_service() {
  echo "Reloading systemd..."
  systemctl daemon-reload

  echo "Enabling and starting ${SERVICE_NAME}..."
  systemctl enable --now "$SERVICE_NAME"
}

show_summary() {
  local backend="$1"
  local gpiochip="$2"
  local status_pin="$3"

  echo
  echo "Install complete."
  echo
  echo "Installed files:"
  echo "  $BIN_MAIN_DST"
  echo "  $BIN_HOLD_DST"
  echo "  $UNIT_MAIN_DST"
  echo "  $HOOK_DST"
  echo
  echo "Reboot hook:"
  echo "  backend   = $backend"
  echo "  gpiochip  = $gpiochip"
  echo "  statuspin = $status_pin"
  echo
  echo "User files:"
  echo "  $CONFIG_DST"
  echo "  $SHUTDOWN_SCRIPT_DST"
  echo
  echo "Service status:"
  systemctl --no-pager --full status "$SERVICE_NAME" || true
}

main() {
  require_root
  bootstrap_if_needed "$@"

  local root
  root="$(repo_root)"

  local status_pin
  local gpiochip
  local hook_backend

  install_main_binaries "$root"
  install_units "$root"
  install_default_config_if_missing
  install_shutdown_helper_if_missing

  status_pin="$(detect_status_pin)"
  gpiochip="$(detect_gpiochip)"
  hook_backend="$(detect_hook_backend)"

  install_reboot_pulse_hook "$status_pin" "$gpiochip" "$hook_backend"

  mkdir -p "$RUNTIME_DIR"
  chmod 0755 "$RUNTIME_DIR"

  cleanup_obsolete_pulse_unit
  disable_legacy_service
  enable_and_start_service
  show_summary "$hook_backend" "$gpiochip" "$status_pin"
}

main "$@"
