#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 1 && "$1" =~ ^[1-9][0-9]*$ ]] || { echo "Usage: $0 SIZE_GIB" >&2; exit 2; }
[[ $EUID != 0 ]] || { echo 'Run as a normal user with sudo.' >&2; exit 1; }
if findmnt -rn /swapfile >/dev/null || [[ -e /swapfile ]]; then echo '/swapfile already exists; no change made.'; exit 0; fi
if [[ "$(findmnt -n -o FSTYPE /)" == btrfs ]]; then
  sudo btrfs filesystem mkswapfile --size "${1}g" /swapfile
else
  sudo fallocate -l "${1}G" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
fi
sudo swapon /swapfile
if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab; then echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab >/dev/null; fi
swapon --show
