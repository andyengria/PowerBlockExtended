```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Support both folder names (future-proof)
if [[ -d "$REPO_DIR/rpi" ]]; then
  SRC_DIR="$REPO_DIR/rpi"
elif [[ -d "$REPO_DIR/raspberrypi" ]]; then
  SRC_DIR="$REPO_DIR/raspberrypi"
else
  echo "Error: could not find rpi/ or raspberrypi/ directory" >&2
  exit 1
fi

SCRIPT_SRC="$SRC_DIR/powerblock-send-reboot-intent.sh"
UNIT_SRC="$SRC_DIR/powerblock-reboot-intent.service"

SCRIPT_DST="/usr/local/bin/powerblock-send-reboot-intent.sh"
UNIT_DST="/etc/systemd/system/powerblock-reboot-intent.service"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command not found: $1" >&2
    exit 1
  }
}

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./install.sh" >&2
  exit 1
fi

need_cmd install
need_cmd systemctl

if [[ ! -f "$SCRIPT_SRC" ]]; then
  echo "Error: missing source script: $SCRIPT_SRC" >&2
  exit 1
fi

if [[ ! -f "$UNIT_SRC" ]]; then
  echo "Error: missing systemd unit: $UNIT_SRC" >&2
  exit 1
fi

echo "Installing reboot-intent script..."
install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"

echo "Installing systemd unit..."
install -m 0644 "$UNIT_SRC" "$UNIT_DST"

echo "Reloading systemd..."
systemctl daemon-reload

echo "Enabling reboot-intent service..."
systemctl enable powerblock-reboot-intent.service

echo
echo "Install complete."
echo
echo "Installed files:"
echo "  $SCRIPT_DST"
echo "  $UNIT_DST"
echo
echo "Next steps:"
echo "  1. Confirm standard PowerBlock service is installed and working"
echo "  2. Reboot and verify quick LED blip"
echo "  3. Confirm Pi restarts without power cut"
```

