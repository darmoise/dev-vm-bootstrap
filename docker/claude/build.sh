#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

sudo docker build \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  --tag claude-by-agent \
  .
