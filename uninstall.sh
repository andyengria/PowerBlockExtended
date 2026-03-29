#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="powerblockenhanced.service"
PULSE_SERVICE_NAME="powerblockenhanced-pulse.service"
LEGACY_SERVICE_NAME="powerblock.service"

BIN_MAIN_DST="/usr/local/sbin/powerblockenhanced"
BIN_HOLD_DST="/usr/local/sbin/powerblockenhanced-hold"
UNIT_MAIN_DST="/etc/systemd/system/powerblockenhanced.service"
UNIT_PULSE_DST="/etc/systemd/system/powerblockenhanced-pulse.service"

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo ./uninstall.sh" >&2
    exit 1
  fi
}

main() {
  require_root

  echo "Stopping and disabling PowerBlockEnhanced..."
  systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable --now "$PULSE_SERVICE_NAME" 2>/dev/null || true

  echo "Removing installed files..."
  rm -f "$BIN_MAIN_DST"
  rm -f "$BIN_HOLD_DST"
  rm -f "$UNIT_MAIN_DST"
  rm -f "$UNIT_PULSE_DST"

  echo "Reloading systemd..."
  systemctl daemon-reload
  systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
  systemctl reset-failed "$PULSE_SERVICE_NAME" 2>/dev/null || true

  if systemctl list-unit-files | grep -q "^${LEGACY_SERVICE_NAME}"; then
    echo
    echo "Legacy ${LEGACY_SERVICE_NAME} is still available on this system."
    echo "Re-enable it manually if you want to return to the original stack:"
    echo "  sudo systemctl unmask ${LEGACY_SERVICE_NAME}"
    echo "  sudo systemctl enable --now ${LEGACY_SERVICE_NAME}"
  fi

  echo
  echo "Uninstall complete."
}

main "$@"
