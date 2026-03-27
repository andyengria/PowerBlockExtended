#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"
TMP_DIR="/tmp/powerblockextended"

SCRIPT_DST="/usr/local/bin/powerblock-send-reboot-intent.sh"
UNIT_DST="/etc/systemd/system/powerblock-reboot-intent.service"

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
need_cmd systemctl
need_cmd install

# Step 1: find local repo files or self-bootstrap from GitHub
if [[ -d "./rpi" || -d "./raspberrypi" ]]; then
  echo "Using local repository files..."
  REPO_DIR="$(pwd)"
else
  echo "Local repo not found, cloning..."
  rm -rf "$TMP_DIR"
  git clone --depth 1 "$REPO_URL" "$TMP_DIR"
  REPO_DIR="$TMP_DIR"
fi

# Step 2: resolve source directory
if [[ -d "$REPO_DIR/rpi" ]]; then
  SRC_DIR="$REPO_DIR/rpi"
elif [[ -d "$REPO_DIR/raspberrypi" ]]; then
  SRC_DIR="$REPO_DIR/raspberrypi"
else
  echo "Error: could not find rpi/ or raspberrypi/ directory in repo" >&2
  exit 1
fi

SCRIPT_SRC="$SRC_DIR/powerblock-send-reboot-intent.sh"
UNIT_SRC="$SRC_DIR/powerblock-reboot-intent.service"

if [[ ! -f "$SCRIPT_SRC" ]]; then
  echo "Error: missing script: $SCRIPT_SRC" >&2
  exit 1
fi

if [[ ! -f "$UNIT_SRC" ]]; then
  echo "Error: missing unit file: $UNIT_SRC" >&2
  exit 1
fi

# Step 3: install files
echo "Installing reboot-intent script..."
install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"

echo "Installing systemd unit..."
install -m 0644 "$UNIT_SRC" "$UNIT_DST"

# Step 4: reload + enable + start
echo "Reloading systemd..."
systemctl daemon-reload

echo "Disabling old reboot-intent unit state if present..."
systemctl disable powerblock-reboot-intent.service 2>/dev/null || true

echo "Enabling reboot-intent service..."
systemctl enable powerblock-reboot-intent.service

echo "Starting reboot-intent service..."
systemctl restart powerblock-reboot-intent.service

echo
echo "Install complete."
echo
echo "Installed:"
echo "  $SCRIPT_DST"
echo "  $UNIT_DST"
echo
echo "Current unit state:"
systemctl status powerblock-reboot-intent.service --no-pager || true
echo
echo "Next steps:"
echo "  1. Confirm standard PowerBlock service is installed and working"
echo "  2. Run: systemctl is-enabled powerblock-reboot-intent.service"
echo "  3. Reboot and verify quick LED blip + power stays on"
