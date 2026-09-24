#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
require_fedora
sudo -v

SOURCE_DIR="$SCRIPT_DIR/docker/claude"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/coding-pc-bootstrap/claude"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/claude"

[[ -f "$SOURCE_DIR/Dockerfile" ]] || die "Missing $SOURCE_DIR/Dockerfile"
[[ -f "$SOURCE_DIR/build.sh" ]] || die "Missing $SOURCE_DIR/build.sh"
[[ -f "$SOURCE_DIR/run.sh" ]] || die "Missing $SOURCE_DIR/run.sh"

log "Installing Docker/Moby if necessary"
if ! command -v docker >/dev/null 2>&1; then
  sudo dnf install -y moby-engine
fi
sudo systemctl enable --now docker.service

log "Installing Claude container launcher into $INSTALL_DIR"
install -d -m 0700 "$INSTALL_DIR" "$BIN_DIR"
install -m 0600 "$SOURCE_DIR/Dockerfile" "$INSTALL_DIR/Dockerfile"
install -m 0600 "$SOURCE_DIR/.dockerignore" "$INSTALL_DIR/.dockerignore"
install -m 0700 "$SOURCE_DIR/build.sh" "$INSTALL_DIR/build.sh"
install -m 0700 "$SOURCE_DIR/run.sh" "$INSTALL_DIR/run.sh"

if [[ -e "$LAUNCHER" && ! -L "$LAUNCHER" ]]; then
  backup="$LAUNCHER.pre-coding-pc-bootstrap.$(date +%Y%m%d%H%M%S)"
  warn "$LAUNCHER already exists and is not a symlink; moving it to $backup"
  mv -- "$LAUNCHER" "$backup"
fi
ln -sfn "$INSTALL_DIR/run.sh" "$LAUNCHER"

ensure_local_bin_on_bash_path

log "Building claude-by-agent image"
"$INSTALL_DIR/build.sh"

cat <<EOF2

Claude launcher installed:
  $LAUNCHER -> $INSTALL_DIR/run.sh

Run:
  claude

If this shell did not already have ~/.local/bin in PATH, either open a new terminal or run:
  source ~/.bashrc
EOF2
