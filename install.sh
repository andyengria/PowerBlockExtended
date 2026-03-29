#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"

# Detect if we are running from repo root
if [ ! -d "rpi" ]; then
    echo "[INFO] Not running from repo — bootstrapping install..."

    TMP_DIR=$(mktemp -d /tmp/powerblockextended.XXXXXX)

    echo "[INFO] Cloning repository into $TMP_DIR..."
    git clone "$REPO_URL" "$TMP_DIR"

    cd "$TMP_DIR"

    echo "[INFO] Re-running install from repo..."
    sudo bash ./install.sh

    echo "[INFO] Cleaning up..."
    rm -rf "$TMP_DIR"

    exit 0
fi

echo "[INFO] Installing PowerBlockEnhanced..."

# Install binaries
sudo install -m 0755 rpi/powerblockenhanced /usr/local/sbin/powerblockenhanced
sudo install -m 0755 rpi/powerblockenhanced-hold /usr/local/sbin/powerblockenhanced-hold

# Install services
sudo install -m 0644 rpi/powerblockenhanced.service /etc/systemd/system/powerblockenhanced.service
sudo install -m 0644 rpi/powerblockenhanced-pulse.service /etc/systemd/system/powerblockenhanced-pulse.service

# Disable legacy service if present
if systemctl list-unit-files | grep -q powerblock.service; then
    echo "[INFO] Disabling legacy powerblock.service..."
    sudo systemctl disable --now powerblock.service || true
    sudo systemctl mask powerblock.service || true
fi

# Reload systemd
sudo systemctl daemon-reload

# Enable and start new service
sudo systemctl enable --now powerblockenhanced.service

echo "[SUCCESS] PowerBlockEnhanced installed and running."
