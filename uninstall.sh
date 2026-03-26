```bash
#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="powerblock-reboot-intent.service"
SCRIPT_PATH="/usr/local/bin/powerblock-send-reboot-intent.sh"
UNIT_PATH="/etc/systemd/system/$SERVICE_NAME"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command not found: $1" >&2
    exit 1
  }
}

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

need_cmd systemctl

echo "Stopping service (if running)..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

echo "Disabling service..."
systemctl disable "$SERVICE_NAME" 2>/dev/null || true

echo "Removing systemd unit..."
if [[ -f "$UNIT_PATH" ]]; then
  rm -f "$UNIT_PATH"
  echo "  removed $UNIT_PATH"
else
  echo "  unit not found (already removed)"
fi

echo "Removing script..."
if [[ -f "$SCRIPT_PATH" ]]; then
  rm -f "$SCRIPT_PATH"
  echo "  removed $SCRIPT_PATH"
else
  echo "  script not found (already removed)"
fi

echo "Reloading systemd..."
systemctl daemon-reload

echo
echo "Uninstall complete."
echo
echo "The standard PowerBlock service was not modified."
echo "Reboot behavior will return to default (power off after reboot)."
```

