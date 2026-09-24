#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/common.sh"
usage() { echo "Usage: $0 [--chat] [--idea] [--agents] [--no-desktop-integration]"; }
CHAT=0; IDEA=0; AGENTS=0; DESKTOP_INTEGRATION=1
while (($#)); do
  case "$1" in
    --chat) CHAT=1;; --idea) IDEA=1;; --agents) AGENTS=1;;
    --no-desktop-integration) DESKTOP_INTEGRATION=0;;
    -h|--help) usage; exit 0;; *) usage; die "Unknown argument: $1";;
  esac
  shift
done
require_not_root
require_fedora
sudo -v
sudo dnf install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent.service
if (( DESKTOP_INTEGRATION )); then
  sudo dnf install -y spice-vdagent
  sudo systemctl enable --now spice-vdagentd.socket
else
  remove_installed_packages spice-vdagent
fi
if (( CHAT || IDEA )); then
  sudo dnf install -y snapd
  sudo systemctl enable --now snapd.socket
  [[ -e /snap || -L /snap ]] || sudo ln -s /var/lib/snapd/snap /snap
  for _ in {1..60}; do
    snap version >/dev/null 2>&1 && break
    sleep 1
  done
  snap version >/dev/null 2>&1 || die "snapd did not become ready"
fi
if (( CHAT )); then
  for app in telegram-desktop slack; do
    snap list "$app" >/dev/null 2>&1 || sudo snap install "$app"
  done
fi
if (( IDEA )); then
  snap list intellij-idea >/dev/null 2>&1 || sudo snap install intellij-idea --classic
fi
if (( AGENTS )); then
  sudo dnf install -y git curl nodejs npm
  if ! command -v codex >/dev/null; then sudo npm install -g @openai/codex; fi
  if ! command -v claude >/dev/null; then
    installer="$(mktemp)"; trap 'rm -f "$installer"' EXIT
    curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh -o "$installer"
    bash "$installer"
  fi
fi
