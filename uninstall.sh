#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/andyengria/PowerBlockExtended.git"
REPO_BRANCH="${REPO_BRANCH:-main}"

SERVICE_NAME="powerblockextended.service"

BIN_MAIN_DST="/usr/local/sbin/powerblockextended"
BIN_HOLD_DST="/usr/local/sbin/powerblockextended-hold"
UNIT_MAIN_DST="/etc/systemd/system/powerblockextended.service"
HOOK_DST="/usr/lib/systemd/system-shutdown/powerblockextended-reboot-pulse"

RUNTIME_DIR="/run/powerblockextended"

CONFIG_DST="/etc/powerblockconfig.cfg"
SHUTDOWN_SCRIPT_DST="/etc/powerblockswitchoff.sh"

# -----------------------------------------------------------------------------

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo ./uninstall.sh" >&2
    exit 1
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

bootstrap_if_needed() {
  local script_path script_dir

  script_path="$(readlink -f "$0" 2>/dev/null || true)"
  script_dir=""

  if [ -n "$script_path" ] && [ -f "$script_path" ]; then
    script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  fi

  # If not running from repo root, bootstrap
  if [ -n "$script_dir" ] && [ -f "${script_dir}/install.sh" ]; then
    return
  fi

  echo "Uninstaller is not running from repository root."
  echo "Bootstrapping repository into /tmp..."

  if ! have_cmd git; then
    echo "ERROR: git is required for bootstrap uninstall." >&2
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d /tmp/powerblockextended.XXXXXX)"
  echo "Cloning ${REPO_URL} (branch: ${REPO_BRANCH}) to ${tmpdir}..."
  git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$tmpdir"

  echo "Re-running uninstaller from cloned repository..."
  exec bash "${tmpdir}/uninstall.sh" "$@"
}

# -----------------------------------------------------------------------------

stop_and_disable_service() {
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
    echo "Stopping and disabling ${SERVICE_NAME}..."
    systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  fi
}

remove_unit() {
  if [ -f "$UNIT_MAIN_DST" ]; then
    echo "Removing systemd unit..."
    rm -f "$UNIT_MAIN_DST"
  fi
}

remove_binaries() {
  echo "Removing binaries..."
  rm -f "$BIN_MAIN_DST"
  rm -f "$BIN_HOLD_DST"
}

remove_hook() {
  if [ -f "$HOOK_DST" ]; then
    echo "Removing reboot pulse hook..."
    rm -f "$HOOK_DST"
  fi
}

remove_runtime_dir() {
  if [ -d "$RUNTIME_DIR" ]; then
    echo "Removing runtime directory..."
    rm -rf "$RUNTIME_DIR"
  fi
}

reload_systemd() {
  echo "Reloading systemd..."
  systemctl daemon-reload
}

# -----------------------------------------------------------------------------
# Optional removal of user config
# -----------------------------------------------------------------------------

maybe_remove_user_files() {
  echo
  echo "Do you want to remove user configuration files?"
  echo "  $CONFIG_DST"
  echo "  $SHUTDOWN_SCRIPT_DST"
  echo
  read -r -p "Remove these files? [y/N]: " ans

  case "$ans" in
    y|Y)
      echo "Removing user config files..."
      rm -f "$CONFIG_DST"
      rm -f "$SHUTDOWN_SCRIPT_DST"
      ;;
    *)
      echo "Preserving user config files."
      ;;
  esac
}

# -----------------------------------------------------------------------------

show_summary() {
  echo
  echo "Uninstall complete."
  echo
  echo "Removed:"
  echo "  $BIN_MAIN_DST"
  echo "  $BIN_HOLD_DST"
  echo "  $UNIT_MAIN_DST"
  echo "  $HOOK_DST"
  echo
  echo "NOTE:"
  echo "  User config files were preserved unless explicitly removed."
}

# -----------------------------------------------------------------------------

main() {
  require_root
  bootstrap_if_needed "$@"

  stop_and_disable_service
  remove_unit
  remove_binaries
  remove_hook
  remove_runtime_dir
  reload_systemd

  maybe_remove_user_files
  show_summary
}

main "$@"
