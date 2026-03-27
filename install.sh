#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"
TMP_DIR="/tmp/powerblockextended"

WRAPPER_DST_BIN="/usr/local/bin/reboot"
WRAPPER_DST_SBIN="/usr/local/sbin/reboot"

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

WRAPPER_SRC="$SRC_DIR/reboot"

if [[ ! -f "$WRAPPER_SRC" ]]; then
  echo "Error: missing reboot wrapper: $WRAPPER_SRC" >&2
  exit 1
fi

echo "Installing reboot wrapper..."
install -m 0755 "$WRAPPER_SRC" "$WRAPPER_DST_BIN"
install -m 0755 "$WRAPPER_SRC" "$WRAPPER_DST_SBIN"

echo
echo "Install complete."
echo
echo "Installed:"
echo "  $WRAPPER_DST_BIN"
echo "  $WRAPPER_DST_SBIN"
echo
echo "Check PATH precedence with:"
echo "  command -v reboot"
echo
echo "Expected result:"
echo "  /usr/local/bin/reboot"
echo "or"
echo "  /usr/local/sbin/reboot"
