#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RPI_DIR="$SCRIPT_DIR/rpi"

SERVICE_NAME="powerblockenhanced.service"
PULSE_SERVICE_NAME="powerblockenhanced-pulse.service"
LEGACY_SERVICE_NAME="powerblock.service"

BIN_MAIN_SRC="$RPI_DIR/powerblockenhanced"
BIN_HOLD_SRC="$RPI_DIR/powerblockenhanced-hold"
UNIT_MAIN_SRC="$RPI_DIR/powerblockenhanced.service"
UNIT_PULSE_SRC="$RPI_DIR/powerblockenhanced-pulse.service"

BIN_MAIN_DST="/usr/local/sbin/powerblockenhanced"
BIN_HOLD_DST="/usr/local/sbin/powerblockenhanced-hold"
UNIT_MAIN_DST="/etc/systemd/system/powerblockenhanced.service"
UNIT_PULSE_DST="/etc/systemd/system/powerblockenhanced-pulse.service"

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo ./install.sh" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

main() {
  require_root

  require_file "$BIN_MAIN_SRC"
  require_file "$BIN_HOLD_SRC"
  require_file "$UNIT_MAIN_SRC"
  require_file "$UNIT_PULSE_SRC"

  echo "Installing PowerBlockEnhanced files..."
  install -m 0755 "$BIN_MAIN_SRC" "$BIN_MAIN_DST"
  install -m 0755 "$BIN_HOLD_SRC" "$BIN_HOLD_DST"
  install -m 0644 "$UNIT_MAIN_SRC" "$UNIT_MAIN_DST"
  install -m 0644 "$UNIT_PULSE_SRC" "$UNIT_PULSE_DST"

  if systemctl list-unit-files | grep -q "^${LEGACY_SERVICE_NAME}"; then
    echo "Disabling legacy ${LEGACY_SERVICE_NAME}..."
    systemctl disable --now "$LEGACY_SERVICE_NAME" || true
    systemctl mask "$LEGACY_SERVICE_NAME" || true
  fi

  if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d powerblock remove || true
  fi

  echo "Reloading systemd..."
  systemctl daemon-reload

  echo "Enabling and starting ${SERVICE_NAME}..."
  systemctl enable --now "$SERVICE_NAME"

  echo
  echo "Install complete."
  echo
  echo "Useful checks:"
  echo "  systemctl status ${SERVICE_NAME}"
  echo "  journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
  echo "  systemctl start ${PULSE_SERVICE_NAME}"
}

main "$@"
