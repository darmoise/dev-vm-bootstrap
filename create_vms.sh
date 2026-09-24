#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: create_vms.sh --iso /path/to/Fedora.iso [options]

Creates exactly one Fedora VM per invocation.

Options:
  --name NAME          VM name (default: fedora-dev)
  --memory MIB        Memory in MiB (default: 12288)
  --disk-size GIB     Maximum sparse disk size in GiB (default: 180)
  --vcpus N           Virtual CPU count (default: 4)
  --disk-dir PATH     VM image directory (default: /var/lib/libvirt/images)
  --no-desktop-integration
                      Disable SPICE clipboard and guest integration channel
  -h, --help          Show this help
USAGE
}

ISO=""
VM_NAME="fedora-dev"
MEMORY_MIB=12288
DISK_SIZE_GIB=180
VCPUS=4
DISK_DIR=/var/lib/libvirt/images
DESKTOP_INTEGRATION=1

while (($#)); do
  case "$1" in
    --iso|--name|--memory|--disk-size|--vcpus|--disk-dir)
      (($# >= 2)) || die "Missing value for $1"
      option="$1"
      shift
      case "$option" in
        --iso) ISO="$1" ;;
        --name) VM_NAME="$1" ;;
        --memory) MEMORY_MIB="$1" ;;
        --disk-size) DISK_SIZE_GIB="$1" ;;
        --vcpus) VCPUS="$1" ;;
        --disk-dir) DISK_DIR="$1" ;;
      esac
      ;;
    --no-desktop-integration) DESKTOP_INTEGRATION=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Unknown argument: $1" ;;
  esac
  shift
done

require_not_root
require_fedora
[[ -f "$ISO" && -r "$ISO" ]] || die "Pass a readable Fedora ISO with --iso"
[[ "$VM_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]] || die "VM name may contain only letters, numbers, dots, underscores and hyphens"
[[ "$MEMORY_MIB" =~ ^[1-9][0-9]*$ ]] || die "Memory must be a positive integer in MiB"
[[ "$DISK_SIZE_GIB" =~ ^[1-9][0-9]*$ ]] || die "Disk size must be a positive integer in GiB"
[[ "$VCPUS" =~ ^[1-9][0-9]*$ ]] || die "vCPU count must be a positive integer"
[[ "$DISK_DIR" == /* && "$DISK_DIR" != *..* ]] || die "Disk directory must be an absolute path without '..'"
[[ -e /dev/kvm ]] || die "KVM unavailable: enable Intel VT-x in firmware and check /dev/kvm"
[[ -e /dev/dri/renderD128 ]] || die "Render node /dev/dri/renderD128 unavailable; 3D acceleration cannot be configured"

space_parent="$DISK_DIR"
while [[ ! -e "$space_parent" ]]; do
  space_parent="$(dirname -- "$space_parent")"
done
free_kib="$(df -Pk "$space_parent" | awk 'END {print $4}')"
required_kib=$(( (DISK_SIZE_GIB + 30) * 1024 * 1024 ))
(( free_kib >= required_kib )) || die "Need at least $((DISK_SIZE_GIB + 30)) GiB free for the VM image and growth"

sudo -v
sudo dnf install -y @virtualization virt-install virt-manager edk2-ovmf qemu-kvm policycoreutils-python-utils
sudo systemctl enable --now libvirtd.service || sudo systemctl enable --now virtqemud.socket
if ! sudo virsh net-info default >/dev/null 2>&1; then
  DEFAULT_NETWORK_XML="/usr/share/libvirt/networks/default.xml"
  [[ -r "$DEFAULT_NETWORK_XML" ]] || die "libvirt default network definition is unavailable"
  sudo virsh net-define "$DEFAULT_NETWORK_XML" >/dev/null
fi
if [[ "$(sudo virsh net-info default | awk '/^Active:/ {print $2}')" != "yes" ]]; then
  sudo virsh net-start default >/dev/null
fi
sudo virsh net-autostart default >/dev/null
if [[ ! -d "$DISK_DIR" ]]; then
  sudo install -d -m 0755 "$DISK_DIR"
fi
if [[ "$DISK_DIR" != "/var/lib/libvirt/images" ]] && command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
  if ! sudo semanage fcontext -a -e /var/lib/libvirt/images "$DISK_DIR" 2>/dev/null; then
    sudo semanage fcontext -m -e /var/lib/libvirt/images "$DISK_DIR"
  fi
  sudo restorecon -RF "$DISK_DIR"
fi

if sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  die "VM $VM_NAME already exists"
fi

DISK_PATH="$DISK_DIR/$VM_NAME.qcow2"
[[ ! -e "$DISK_PATH" ]] || die "Disk $DISK_PATH already exists; refusing to overwrite"

# System QEMU often cannot traverse a user's home directory. Keep a content-addressed
# copy in libvirt storage so equal filenames cannot overwrite each other.
ISO_DIR="/var/lib/libvirt/boot/coding-pc-bootstrap"
sudo install -d -m 0755 "$ISO_DIR"
ISO_NAME="$(basename -- "$ISO")"
ISO_HASH="$(sha256sum -- "$ISO" | awk '{print $1}')"
LIBVIRT_ISO="$ISO_DIR/$ISO_HASH-$ISO_NAME"
CACHED_HASH=""
if [[ -r "$LIBVIRT_ISO" ]]; then
  CACHED_HASH="$(sha256sum -- "$LIBVIRT_ISO" | awk '{print $1}')"
fi
if [[ "$CACHED_HASH" != "$ISO_HASH" ]]; then
  ISO_BYTES="$(stat -c %s -- "$ISO")"
  ISO_DIR_FREE_BYTES="$(df -PB1 "$ISO_DIR" | awk 'END {print $4}')"
  (( ISO_DIR_FREE_BYTES >= ISO_BYTES + 1073741824 )) || die "Not enough free space to cache the ISO in $ISO_DIR"
  log "Copying the ISO into libvirt storage"
  PARTIAL_ISO="$LIBVIRT_ISO.partial.$$"
  sudo install -m 0644 "$ISO" "$PARTIAL_ISO"
  sudo mv -f -- "$PARTIAL_ISO" "$LIBVIRT_ISO"
  command -v restorecon >/dev/null 2>&1 && sudo restorecon "$LIBVIRT_ISO" || true
fi

CHANNEL_ARGS=(--channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0)
if (( DESKTOP_INTEGRATION )); then
  CHANNEL_ARGS+=(--channel spicevmc)
fi

sudo virt-install \
  --connect qemu:///system \
  --name "$VM_NAME" \
  --memory "$MEMORY_MIB" \
  --vcpus "$VCPUS" \
  --cpu host-passthrough \
  --machine q35 \
  --boot uefi \
  --disk "path=$DISK_PATH,size=$DISK_SIZE_GIB,format=qcow2,bus=virtio" \
  --cdrom "$LIBVIRT_ISO" \
  --network network=default,model=virtio \
  --graphics spice,listen=none,gl.enable=yes,gl.rendernode=/dev/dri/renderD128 \
  --video virtio,accel3d=yes \
  "${CHANNEL_ARGS[@]}" \
  --sound ich9 \
  --noautoconsole \
  --wait 0

echo "VM $VM_NAME created."
echo "Open virt-manager and install Fedora manually."
if (( DESKTOP_INTEGRATION )); then
  echo "After installation, run init_guest_apps.sh in the guest to enable clipboard integration."
else
  echo "Desktop integration was disabled for this VM."
fi
echo "Configure swap in the installer or run setup_guest_swap.sh afterward."
echo "To create another VM later, run this script again with a different --name."
