#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_ROOT="$HOME/IdeaProjects/by-agent"
DOCKER_NETWORK="claude-by-agent-net"

[[ -d "$AGENT_ROOT" ]] || {
  echo "Agent projects directory does not exist: $AGENT_ROOT" >&2
  echo "Run init_dev.sh first." >&2
  exit 1
}

BASE_PATH="$(realpath -e -- "$AGENT_ROOT")"

# -------------------------
# Select organization
# -------------------------
mapfile -d '' ORGANIZATIONS < <(
  find "$BASE_PATH" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '%f\0' |
  sort -z
)

if (( ${#ORGANIZATIONS[@]} == 0 )); then
  echo "No organizations found in $BASE_PATH."
  exit 1
fi

echo "Select organization:"
echo
for i in "${!ORGANIZATIONS[@]}"; do
  printf '%d) %s\n' "$((i + 1))" "${ORGANIZATIONS[$i]}"
done
echo "0) Cancel"
echo

while true; do
  read -rp "> " choice
  if [[ "$choice" == "0" ]]; then
    exit 0
  fi
  if [[ "$choice" =~ ^[0-9]+$ ]] &&
     (( choice >= 1 && choice <= ${#ORGANIZATIONS[@]} )); then
    ORGANIZATION="${ORGANIZATIONS[$((choice - 1))]}"
    break
  fi
  echo "Invalid selection."
done

# -------------------------
# Select project
# -------------------------
ORG_PATH="$BASE_PATH/$ORGANIZATION"
mapfile -d '' PROJECTS < <(
  find "$ORG_PATH" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '%f\0' |
  sort -z
)

if (( ${#PROJECTS[@]} == 0 )); then
  echo
  echo "No projects found in organization '$ORGANIZATION'."
  exit 1
fi

echo
echo "Select project in $ORGANIZATION:"
echo
for i in "${!PROJECTS[@]}"; do
  printf '%d) %s\n' "$((i + 1))" "${PROJECTS[$i]}"
done
echo "0) Cancel"
echo

while true; do
  read -rp "> " choice
  if [[ "$choice" == "0" ]]; then
    exit 0
  fi
  if [[ "$choice" =~ ^[0-9]+$ ]] &&
     (( choice >= 1 && choice <= ${#PROJECTS[@]} )); then
    PROJECT="${PROJECTS[$((choice - 1))]}"
    break
  fi
  echo "Invalid selection."
done

# -------------------------
# Validate mount path
# -------------------------
for component in "$ORGANIZATION" "$PROJECT"; do
  [[ "$component" != *','* ]] || {
    echo "Organization/project names must not contain a comma." >&2
    exit 1
  }
  [[ ! "$component" =~ [[:cntrl:]] ]] || {
    echo "Organization/project names must not contain control characters." >&2
    exit 1
  }
done

CANDIDATE="$ORG_PATH/$PROJECT"
[[ -d "$CANDIDATE" ]] || {
  echo "Project directory does not exist: $CANDIDATE" >&2
  exit 1
}

PROJECT_PATH="$(realpath -e -- "$CANDIDATE")"
case "$PROJECT_PATH" in
  "$BASE_PATH"/*) ;;
  *)
    echo "Resolved project path escapes the allowed agent root:" >&2
    echo "  $PROJECT_PATH" >&2
    exit 1
    ;;
esac

# Do not pass host IPC/device endpoints through the project bind mount.
SPECIAL_FILE="$(find -P "$PROJECT_PATH" -xdev \( -type s -o -type b -o -type c \) -print -quit)"
if [[ -n "$SPECIAL_FILE" ]]; then
  echo "Refusing to mount a project containing a socket/device node:" >&2
  echo "  $SPECIAL_FILE" >&2
  echo "Remove it or move it outside the project tree before starting Claude." >&2
  exit 1
fi

# Per-project writable cache/toolchain volume. This avoids sharing Gradle/Maven
# writable state between unrelated repositories.
PROJECT_ID="$(printf '%s' "$PROJECT_PATH" | sha256sum | cut -c1-16)"
AGENT_DATA_VOLUME="claude-by-agent-data-$PROJECT_ID"

# Optional resource limits can be set without editing this script:
#   CLAUDE_MEMORY=12g CLAUDE_CPUS=6 CLAUDE_PIDS_LIMIT=2048 claude
DOCKER_LIMIT_ARGS=(--pids-limit="${CLAUDE_PIDS_LIMIT:-2048}")
if [[ -n "${CLAUDE_MEMORY:-}" ]]; then
  DOCKER_LIMIT_ARGS+=(--memory="$CLAUDE_MEMORY")
fi
if [[ -n "${CLAUDE_CPUS:-}" ]]; then
  DOCKER_LIMIT_ARGS+=(--cpus="$CLAUDE_CPUS")
fi

# -------------------------
# Start agent
# -------------------------
echo
echo "Starting agent"
echo "Organization: $ORGANIZATION"
echo "Project:      $PROJECT"
echo "Host path:    $PROJECT_PATH"
echo

# Keep Claude off Docker's shared default bridge. This still allows Internet
# egress, which Claude requires, but isolates it from containers on default.
if ! sudo docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
  sudo docker network create --driver bridge "$DOCKER_NETWORK" >/dev/null
fi

sudo docker run --rm -it \
  --name claude-by-agent \
  --pull=never \
  --user "$(id -u):$(id -g)" \
  --cap-drop=ALL \
  --security-opt=no-new-privileges=true \
  --read-only \
  --cgroupns=private \
  --network="$DOCKER_NETWORK" \
  "${DOCKER_LIMIT_ARGS[@]}" \
  --init \
  --tmpfs /tmp:rw,nosuid,nodev,mode=1777,size=2g \
  -e CLAUDE_CONFIG_DIR=/home/developer/.claude \
  --mount type=volume,src=claude-by-agent-config,dst=/home/developer/.claude \
  --mount type=volume,src="$AGENT_DATA_VOLUME",dst=/home/developer/.agent-data \
  --mount "type=bind,src=$PROJECT_PATH,dst=/workspace,bind-recursive=disabled" \
  --workdir /workspace \
  claude-by-agent
