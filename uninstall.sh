#!/usr/bin/env bash
set -euo pipefail

POWERBLOCK_UNIT="powerblock.service"

DROPIN_DIR="/etc/systemd/system/${POWERBLOCK_UNIT}.d"
DROPIN_DST="${DROPIN_DIR}/powerblock-reboot-intent.conf"
HELPER_DST="/usr/local/bin/powerblock-send-reboot-intent-if-reboot.sh"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

if [[ -f "$DROPIN_DST" ]]; then
  echo "Removing systemd drop-in..."
  rm -f "$DROPIN_DST"
else
  echo "Drop-in not present: $DROPIN_DST"
fi

if [[ -f "$HELPER_DST" ]]; then
  echo "Removing helper script..."
  rm -f "$HELPER_DST"
else
  echo "Helper script not present: $HELPER_DST"
fi

if [[ -d "$DROPIN_DIR" ]] && [[ -z "$(ls -A "$DROPIN_DIR" 2>/dev/null)" ]]; then
  echo "Removing empty drop-in directory..."
  rmdir "$DROPIN_DIR"
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload

if systemctl list-unit-files --no-legend --no-pager | awk '{print $1}' | grep -Fxq "$POWERBLOCK_UNIT"; then
  if systemctl is-active --quiet "$POWERBLOCK_UNIT"; then
    echo "Restarting ${POWERBLOCK_UNIT}..."
    systemctl restart "$POWERBLOCK_UNIT" || true
  fi
fi

echo
echo "Uninstall complete."
echo "The reboot-intent drop-in and helper script have been removed."
