#!/usr/bin/env bash
set -euo pipefail

POWERBLOCK_INIT="/etc/init.d/powerblock"
HELPER_DST="/usr/local/bin/powerblock-send-reboot-intent-if-reboot.sh"
MARKER_UNIT_DST="/etc/systemd/system/powerblock-reboot-marker.service"
DROPIN_DST="/etc/systemd/system/powerblock.service.d/powerblock-reboot-intent.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

echo "Removing helper script..."
rm -f "$HELPER_DST"

echo "Disabling reboot marker unit..."
systemctl disable powerblock-reboot-marker.service >/dev/null 2>&1 || true

echo "Removing reboot marker unit..."
rm -f "$MARKER_UNIT_DST"

echo "Removing old drop-in if present..."
rm -f "$DROPIN_DST" || true
rmdir /etc/systemd/system/powerblock.service.d 2>/dev/null || true

if [[ -f "$POWERBLOCK_INIT" ]]; then
  echo "Removing init-script patch..."
  python3 - "$POWERBLOCK_INIT" <<'PY'
from pathlib import Path
import sys
import re

path = Path(sys.argv[1])
text = path.read_text()

text = re.sub(
    r'\n?# BEGIN PowerBlockExtended reboot-intent patch.*?# END PowerBlockExtended reboot-intent patch\n?',
    '\n',
    text,
    flags=re.S
)

path.write_text(text)
PY
  chmod 0755 "$POWERBLOCK_INIT"
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload

if systemctl list-unit-files --no-legend --no-pager | awk '{print $1}' | grep -Fxq "powerblock.service"; then
  if systemctl is-active --quiet powerblock.service; then
    echo "Restarting powerblock.service..."
    systemctl restart powerblock.service || true
  fi
fi

echo
echo "Uninstall complete."
echo "The reboot-intent helper, marker unit, and init-script patch have been removed."
