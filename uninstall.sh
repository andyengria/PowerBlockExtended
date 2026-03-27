#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

rm -f /usr/local/bin/reboot
rm -f /usr/local/sbin/reboot

echo "Uninstall complete."
echo "The system will now use the default reboot command again."
