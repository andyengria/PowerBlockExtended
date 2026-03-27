#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"
TMP_DIR="/tmp/powerblockextended"

POWERBLOCK_UNIT="powerblock.service"

DROPIN_DIR="/etc/systemd/system/${POWERBLOCK_UNIT}.d"
DROPIN_DST="${DROPIN_DIR}/powerblock-reboot-intent.conf"
HELPER_DST="/usr/local/bin/powerblock-send-reboot-intent-if-reboot.sh"

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

DROPIN_SRC="$SRC_DIR/powerblock-reboot-intent-dropin.service"
HELPER_SRC="$SRC_DIR/powerblock-send-reboot-intent-if-reboot.sh"

if [[ ! -f "$DROPIN_SRC" ]]; then
  echo "Error: missing drop-in file: $DROPIN_SRC" >&2
  exit 1
fi

if [[ ! -f "$HELPER_SRC" ]]; then
  echo "Error: missing helper script: $HELPER_SRC" >&2
  exit 1
fi

echo "Creating systemd drop-in directory..."
install -d -m 0755 "$DROPIN_DIR"

echo "Installing systemd drop-in..."
install -m 0644 "$DROPIN_SRC" "$DROPIN_DST"

echo "Installing reboot-intent helper script..."
install -m 0755 "$HELPER_SRC" "$HELPER_DST"

echo "Reloading systemd daemon..."
systemctl daemon-reload

if systemctl list-unit-files --no-legend --no-pager | awk '{print $1}' | grep -Fxq "$POWERBLOCK_UNIT"; then
  echo "Found ${POWERBLOCK_UNIT}"

  if systemctl is-enabled --quiet "$POWERBLOCK_UNIT" 2>/dev/null; then
    :
  else
    echo "Enabling ${POWERBLOCK_UNIT}..."
    systemctl enable "$POWERBLOCK_UNIT" >/dev/null 2>&1 || true
  fi

  if systemctl is-active --quiet "$POWERBLOCK_UNIT"; then
    echo "Restarting ${POWERBLOCK_UNIT}..."
    systemctl restart "$POWERBLOCK_UNIT"
  else
    echo "Starting ${POWERBLOCK_UNIT}..."
    systemctl start "$POWERBLOCK_UNIT" || true
  fi
else
  echo "Warning: ${POWERBLOCK_UNIT} was not found."
  echo "The drop-in and helper were installed, but the native PowerBlock service does not appear to be installed yet."
fi

echo
echo "Install complete."
echo
echo "Installed:"
echo "  $DROPIN_DST"
echo "  $HELPER_DST"
echo
echo "Inspect merged unit with:"
echo "  systemctl cat ${POWERBLOCK_UNIT}"
echo
echo "Check helper presence with:"
echo "  ls -l ${HELPER_DST}"
