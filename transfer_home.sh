#!/usr/bin/env bash
set -Eeuo pipefail
# Run on host. Default is a preview. Guest SSH must be enabled and reachable.
usage() { echo "Usage: $0 USER@GUEST [--apply]"; }
[[ $# -ge 1 ]] || { usage; exit 2; }
target="$1"; shift
[[ "$target" =~ ^[a-zA-Z_][a-zA-Z_0-9.-]*@[a-zA-Z0-9._-]+$ ]] || { usage; exit 2; }
apply=0
while (($#)); do case "$1" in --apply) apply=1;; *) usage; exit 2;; esac; shift; done
command -v rsync >/dev/null || { echo 'Install rsync on both host and guest.' >&2; exit 1; }
ssh -o StrictHostKeyChecking=ask "$target" 'command -v rsync >/dev/null && test -w "$HOME"' || { echo 'SSH/rsync unavailable on guest.' >&2; exit 1; }
opts=(
  -aH
  --info=stats2
  --exclude=/Downloads/
  --exclude=/.cache/
  --exclude=/.local/share/Trash/
  --exclude=/.local/share/keyrings/
  --exclude=/.ssh/
  --exclude=/.gnupg/
  --exclude=/.pki/
  --exclude=/.config/Code/User/globalStorage/
  --exclude=/.mozilla/firefox/*/logins.json
  --exclude=/.mozilla/firefox/*/key4.db
  --exclude=/.mozilla/firefox/*/cert9.db
)
(( apply )) || opts+=(--dry-run --itemize-changes)
rsync "${opts[@]}" -e 'ssh -o StrictHostKeyChecking=ask' "$HOME/" "$target":~/
if (( apply )); then
  echo 'Copy complete. Inspect Firefox bookmarks, Git config, projects and secrets in guest before cleanup.'
fi
