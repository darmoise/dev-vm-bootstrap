#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() { echo "Usage: $0 [--remove-extra-apps]"; }
REMOVE_EXTRA_APPS=0
while (($#)); do
  case "$1" in
    --remove-extra-apps) REMOVE_EXTRA_APPS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Unknown argument: $1" ;;
  esac
  shift
done

require_not_root
require_fedora
sudo -v

log "Installing GNOME extension tooling and Dash to Dock"
sudo dnf install -y \
  gnome-extensions-app \
  gnome-shell-extension-dash-to-dock

if (( REMOVE_EXTRA_APPS )); then
  log "Removing unwanted desktop software"
  # Keep this list conservative. Add packages here only when you are sure they are disposable.
  remove_installed_packages \
    gnome-tour \
    gnome-chess \
    gnome-mahjongg \
    gnome-mines \
    gnome-sudoku \
    aisleriot

  mapfile -t libreoffice_packages < <(rpm -qa --qf '%{NAME}\n' | grep -E '^libreoffice($|-)' | sort -u || true)
  if (( ${#libreoffice_packages[@]} > 0 )); then
    sudo dnf remove -y "${libreoffice_packages[@]}"
  fi

fi

log "Configuring Dash to Dock"
SCHEMA="org.gnome.shell.extensions.dash-to-dock"
if gsettings list-schemas | grep -qx "$SCHEMA"; then
  gsettings set org.gnome.shell disable-user-extensions false
  gsettings set "$SCHEMA" dock-position 'LEFT'
  gsettings set "$SCHEMA" dock-fixed true
  gsettings set "$SCHEMA" autohide false
  gsettings set "$SCHEMA" intellihide false
else
  warn "Dash to Dock schema is not visible in this session yet. Log out/in once, then re-run init_de.sh."
fi

EXTENSION_UUID="dash-to-dock@micxgx.gmail.com"
if command -v gnome-extensions >/dev/null 2>&1; then
  if gnome-extensions list 2>/dev/null | grep -qx "$EXTENSION_UUID"; then
    gnome-extensions enable "$EXTENSION_UUID" || warn "Could not enable Dash to Dock in the current GNOME session. Log out/in and enable it from the Extensions app."
  else
    warn "Dash to Dock is installed system-wide but GNOME has not loaded it into this session yet. Log out/in once."
  fi
fi

cat <<'EOF2'

Desktop setup complete.
Dash to Dock settings requested:
  position: left
  fixed:    yes
  autohide: off
  intellihide: off

A GNOME logout/login may be required before a newly installed shell extension can be enabled.
EOF2
