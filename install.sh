#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"
TMP_DIR="/tmp/powerblockextended"

POWERBLOCK_INIT="/etc/init.d/powerblock"
HELPER_DST="/usr/local/bin/powerblock-send-reboot-intent-if-reboot.sh"
MARKER_UNIT_DST="/etc/systemd/system/powerblock-reboot-marker.service"
DROPIN_DST="/etc/systemd/system/powerblock.service.d/powerblock-reboot-intent.conf"

PATCH_BEGIN="# BEGIN PowerBlockExtended reboot-intent patch"
PATCH_END="# END PowerBlockExtended reboot-intent patch"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command not found: $1" >&2
    exit 1
  }
}

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash install.sh" >&2
  exit 1
fi

need_cmd git
need_cmd install
need_cmd systemctl
need_cmd python3

if [[ -d "./rpi" || -d "./raspberrypi" ]]; then
  echo "Using local repository files..."
  REPO_DIR="$(pwd)"
else
  echo "Local repo not found, cloning..."
  rm -rf "$TMP_DIR"
  git clone --depth 1 "$REPO_URL" "$TMP_DIR"
  REPO_DIR="$TMP_DIR"
fi

if [[ -d "$REPO_DIR/rpi" ]]; then
  SRC_DIR="$REPO_DIR/rpi"
elif [[ -d "$REPO_DIR/raspberrypi" ]]; then
  SRC_DIR="$REPO_DIR/raspberrypi"
else
  echo "Error: could not find rpi/ or raspberrypi/ directory in repo" >&2
  exit 1
fi

HELPER_SRC="$SRC_DIR/powerblock-send-reboot-intent-if-reboot.sh"
MARKER_UNIT_SRC="$SRC_DIR/powerblock-reboot-marker.service"

if [[ ! -f "$HELPER_SRC" ]]; then
  echo "Error: missing helper script: $HELPER_SRC" >&2
  exit 1
fi

if [[ ! -f "$MARKER_UNIT_SRC" ]]; then
  echo "Error: missing marker unit: $MARKER_UNIT_SRC" >&2
  exit 1
fi

if [[ ! -f "$POWERBLOCK_INIT" ]]; then
  echo "Error: expected init script not found: $POWERBLOCK_INIT" >&2
  exit 1
fi

echo "Installing reboot-intent helper script..."
install -m 0755 "$HELPER_SRC" "$HELPER_DST"

echo "Installing reboot marker unit..."
install -m 0644 "$MARKER_UNIT_SRC" "$MARKER_UNIT_DST"

echo "Removing old drop-in if present..."
rm -f "$DROPIN_DST" || true
rmdir /etc/systemd/system/powerblock.service.d 2>/dev/null || true

echo "Patching $POWERBLOCK_INIT ..."
python3 - "$POWERBLOCK_INIT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

patch_begin = "# BEGIN PowerBlockExtended reboot-intent patch"
patch_end = "# END PowerBlockExtended reboot-intent patch"

block = """# BEGIN PowerBlockExtended reboot-intent patch
send_reboot_intent()
{
    /usr/local/bin/powerblock-send-reboot-intent-if-reboot.sh || true
}
# END PowerBlockExtended reboot-intent patch
"""

needle_func = "do_stop()\n{"
if patch_begin not in text:
    if needle_func not in text:
        raise SystemExit("Could not find do_stop() in init script.")
    text = text.replace(needle_func, block + "\n" + needle_func, 1)

needle_stop = '    start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --name $NAME'
replacement_stop = '''    # BEGIN PowerBlockExtended reboot-intent patch
    send_reboot_intent
    # END PowerBlockExtended reboot-intent patch
    start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --name $NAME'''

if "send_reboot_intent" not in text or replacement_stop not in text:
    if needle_stop not in text:
        raise SystemExit("Could not find start-stop-daemon stop call in init script.")
    text = text.replace(needle_stop, replacement_stop, 1)

path.write_text(text)
PY

chmod 0755 "$POWERBLOCK_INIT"

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling reboot marker unit..."
systemctl enable powerblock-reboot-marker.service

if systemctl list-unit-files --no-legend --no-pager | awk '{print $1}' | grep -Fxq "powerblock.service"; then
  if systemctl is-active --quiet powerblock.service; then
    echo "Restarting powerblock.service..."
    systemctl restart powerblock.service || true
  else
    echo "Starting powerblock.service..."
    systemctl start powerblock.service || true
  fi
fi

echo
echo "Install complete."
echo
echo "Installed:"
echo "  $HELPER_DST"
echo "  $MARKER_UNIT_DST"
echo
echo "Patched:"
echo "  $POWERBLOCK_INIT"
echo
echo "Verify with:"
echo "  systemctl cat powerblock.service"
echo "  systemctl cat powerblock-reboot-marker.service"
echo "  grep -n 'send_reboot_intent' $POWERBLOCK_INIT"
