#!/usr/bin/env bash

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_fedora() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "fedora" ]] || die "This bootstrap is intended for Fedora (detected: ${PRETTY_NAME:-unknown})."
}

require_not_root() {
  (( EUID != 0 )) || die "Run this script as your normal user, not as root. It will call sudo when needed."
}

ensure_local_bin_on_bash_path() {
  local bashrc="$HOME/.bashrc"
  local marker_begin="# >>> coding-pc-bootstrap local-bin >>>"

  mkdir -p "$HOME/.local/bin"
  touch "$bashrc"

  if ! grep -Fq "$marker_begin" "$bashrc"; then
    cat >> "$bashrc" <<'SNIPPET'

# >>> coding-pc-bootstrap local-bin >>>
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# <<< coding-pc-bootstrap local-bin <<<
SNIPPET
  fi
}

remove_installed_packages() {
  local -a requested=("$@")
  local -a installed=()
  local package

  for package in "${requested[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then
      installed+=("$package")
    fi
  done

  if (( ${#installed[@]} > 0 )); then
    sudo dnf remove -y "${installed[@]}"
  fi
}
