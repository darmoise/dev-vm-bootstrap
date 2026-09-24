#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=config/android-studio.env
source "$SCRIPT_DIR/config/android-studio.env"

usage() { echo "Usage: $0 [--android] [--backend]"; }
ANDROID=0; BACKEND=0
while (($#)); do
  case "$1" in --android) ANDROID=1;; --backend) BACKEND=1;; -h|--help) usage; exit 0;; *) usage; die "Unknown argument: $1";; esac
  shift
done
(( ANDROID || BACKEND )) || { usage; exit 2; }
require_not_root
require_fedora
sudo -v

PROJECTS_ROOT="$HOME/IdeaProjects"
AGENT_ROOT="$PROJECTS_ROOT/by-agent"
DEV_ROOT="$PROJECTS_ROOT/by-dev"
ANDROID_STUDIO_DIR="$HOME/.local/opt/android-studio"
ANDROID_STUDIO_DESKTOP="$HOME/.local/share/applications/android-studio.desktop"

log "Installing development prerequisites"
sudo dnf install -y \
  git \
  curl \
  tar \
  gzip \
  coreutils \
  policycoreutils-python-utils \
  openssh-clients

log "Creating generic project directories"
install -d -m 0750 "$AGENT_ROOT" "$DEV_ROOT"

log "Preparing SELinux labels for agent-accessible projects"
if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
  FCONTEXT_REGEX="${AGENT_ROOT}(/.*)?"
  if ! sudo semanage fcontext -a -t container_file_t "$FCONTEXT_REGEX" 2>/dev/null; then
    sudo semanage fcontext -m -t container_file_t "$FCONTEXT_REGEX"
  fi
  sudo restorecon -RF "$AGENT_ROOT"
fi

if (( BACKEND )); then
  log "Installing backend tools"
  sudo dnf install -y java-latest-openjdk-devel maven podman nodejs npm python3 python3-pip snapd
  sudo systemctl enable --now snapd.socket
  [[ -e /snap || -L /snap ]] || sudo ln -s /var/lib/snapd/snap /snap
  for _ in {1..60}; do
    snap version >/dev/null 2>&1 && break
    sleep 1
  done
  snap version >/dev/null 2>&1 || die "snapd did not become ready"

  log "Installing IntelliJ IDEA via Snap"
  if ! snap list intellij-idea >/dev/null 2>&1; then
    sudo snap install intellij-idea --classic
  else
    printf 'IntelliJ IDEA snap is already installed.\n'
  fi
fi

install_android_studio() (
  local current_version=""
  local temp_dir archive extracted

  if [[ -r "$ANDROID_STUDIO_DIR/.coding-pc-bootstrap-version" ]]; then
    current_version="$(<"$ANDROID_STUDIO_DIR/.coding-pc-bootstrap-version")"
  fi

  if [[ "$current_version" == "$ANDROID_STUDIO_VERSION" ]]; then
    printf 'Android Studio %s is already installed at %s.\n' "$ANDROID_STUDIO_VERSION" "$ANDROID_STUDIO_DIR"
    return
  fi

  temp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temp_dir"' EXIT
  archive="$temp_dir/$ANDROID_STUDIO_ARCHIVE"

  log "Downloading Android Studio $ANDROID_STUDIO_VERSION"
  curl --proto '=https' --tlsv1.2 \
    --fail --location --show-error --silent \
    --retry 3 --retry-delay 2 \
    --output "$archive" \
    "$ANDROID_STUDIO_URL"

  log "Verifying Android Studio SHA-256"
  printf '%s  %s\n' "$ANDROID_STUDIO_SHA256" "$archive" | sha256sum --check --strict -

  log "Installing Android Studio into $ANDROID_STUDIO_DIR"
  tar -xzf "$archive" -C "$temp_dir"
  extracted="$temp_dir/android-studio"
  [[ -x "$extracted/bin/studio" ]] || die "Downloaded archive does not contain android-studio/bin/studio"

  install -d -m 0755 "$(dirname -- "$ANDROID_STUDIO_DIR")"
  rm -rf -- "$ANDROID_STUDIO_DIR"
  mv -- "$extracted" "$ANDROID_STUDIO_DIR"
  printf '%s\n' "$ANDROID_STUDIO_VERSION" > "$ANDROID_STUDIO_DIR/.coding-pc-bootstrap-version"

  # The archive has been verified and is no longer needed.
  rm -f -- "$archive"
)

if (( ANDROID )); then
  sudo dnf install -y zlib.i686 ncurses-libs.i686 bzip2-libs.i686
  install_android_studio

  log "Creating Android Studio command and desktop entry"
  install -d -m 0755 "$HOME/.local/bin" "$HOME/.local/share/applications"
  ln -sfn "$ANDROID_STUDIO_DIR/bin/studio" "$HOME/.local/bin/android-studio"

  cat > "$ANDROID_STUDIO_DESKTOP" <<EOF2
[Desktop Entry]
Version=1.0
Type=Application
Name=Android Studio
Comment=Android development environment
Exec=$ANDROID_STUDIO_DIR/bin/studio %f
Icon=$ANDROID_STUDIO_DIR/bin/studio.svg
Terminal=false
Categories=Development;IDE;
StartupWMClass=jetbrains-android-studio
EOF2
  chmod 0644 "$ANDROID_STUDIO_DESKTOP"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ensure_local_bin_on_bash_path
fi

cat <<EOF2

Development setup complete.

Project roots:
  $AGENT_ROOT
  $DEV_ROOT

No Git identity is created or changed.
Android profile: $ANDROID
Backend profile: $BACKEND
EOF2
