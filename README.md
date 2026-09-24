# Fedora VM Bootstrap

Scripts for creating one Fedora virtual machine at a time on a Fedora GNOME host and configuring the installed guest. The default VM is intended for development, but every resource setting can be overridden. Personal Git identities, organization names, passwords and private project paths are not configured.

## Requirements

Host requirements:

- Fedora with sudo access.
- Hardware virtualization enabled and `/dev/kvm` available.
- An Intel or another Mesa compatible render node at `/dev/dri/renderD128`.
- A downloaded Fedora ISO whose checksum you have verified.
- Enough physical RAM and disk space for the selected VM configuration.

Run scripts as your normal user. They invoke `sudo` for system changes.

## Quick start

Create one VM on the host:

```bash
./create_vms.sh --iso ~/Downloads/Fedora-Workstation-Live-x86_64.iso
virt-manager
```

The default VM is named `fedora-dev` and receives:

- 12 GiB RAM;
- four vCPUs;
- a sparse qcow2 disk with a maximum size of 180 GiB;
- UEFI, Q35 and virtio devices;
- accelerated virtio 3D graphics;
- SPICE clipboard and display resize support;
- a QEMU guest agent channel;
- libvirt's default NAT network.

Install Fedora manually in the virt-manager console. Then copy or clone this repository into the guest and run:

```bash
./init_guest_apps.sh --chat --idea --agents
./setup_guest_swap.sh 8
./init_dev.sh --android --backend
```

`init_guest_apps.sh` installs `spice-vdagent` and `qemu-guest-agent` by default. Clipboard sharing and automatic display resizing become available after the guest agent starts; logging out or rebooting once may be needed after its first installation.

## VM creation examples

### Default development VM

```bash
./create_vms.sh --iso /path/to/Fedora.iso
```

### One VM with custom resources

Memory is specified in MiB. Disk size is specified in GiB.

```bash
./create_vms.sh \
  --iso /path/to/Fedora.iso \
  --name fedora-work \
  --memory 16384 \
  --disk-size 220 \
  --vcpus 6
```

### Store the virtual disk elsewhere

```bash
./create_vms.sh \
  --iso /path/to/Fedora.iso \
  --name fedora-dev \
  --disk-dir /mnt/fast-ssd/libvirt
```

### Create another VM later

The script creates exactly one VM per invocation. Run it again with a unique name when another VM is needed:

```bash
./create_vms.sh \
  --iso /path/to/Fedora-Xfce.iso \
  --name fedora-secondary \
  --memory 6144 \
  --disk-size 80 \
  --vcpus 2
```

### Disable desktop integration

Pass the flag during VM creation and guest setup:

```bash
./create_vms.sh \
  --iso /path/to/Fedora.iso \
  --name fedora-isolated \
  --no-desktop-integration
```

Inside that guest:

```bash
./init_guest_apps.sh --agents --no-desktop-integration
```

The QEMU guest agent remains enabled for lifecycle operations and IP reporting. The flag disables the SPICE agent channel and removes `spice-vdagent`, which disables shared clipboard and automatic display resizing.

## Graphics and ISO handling

The VM uses virtio 3D with SPICE GL backed by `/dev/dri/renderD128`. Rendering is performed through the host render node while the integrated GPU remains available to the host. This is accelerated virtual graphics.

System QEMU often cannot read an ISO located below a user's home directory. The script hashes the ISO and copies it to `/var/lib/libvirt/boot/coding-pc-bootstrap/`. Reusing the same ISO reuses that copy. Cached ISO files can be removed manually after no VM needs them as mounted installation media.

The VM disk is sparse and grows as data is written. Before creation, the script requires free space equal to the configured maximum disk size plus 30 GiB. Existing VM definitions and disk files are never overwritten.

## Guest application examples

Run the command with no app flags to install only the default guest integration:

```bash
./init_guest_apps.sh
```

Select any combination of app groups:

```bash
./init_guest_apps.sh --chat
./init_guest_apps.sh --idea
./init_guest_apps.sh --agents
./init_guest_apps.sh --chat --idea --agents
```

The groups install:

- `--chat`: Telegram Desktop and Slack from Snap;
- `--idea`: IntelliJ IDEA from Snap;
- `--agents`: Claude Code and the Codex CLI.

App account sign-in remains interactive. IntelliJ IDEA is distributed as a unified Snap; paid features require the corresponding JetBrains license.

## Development profiles

Install either profile or both:

```bash
./init_dev.sh --android
./init_dev.sh --backend
./init_dev.sh --android --backend
```

The Android profile installs the pinned Android Studio release from `config/android-studio.env` after verifying its SHA-256 checksum. The backend profile installs Java, Maven, Podman, Node.js, Python and IntelliJ IDEA.

The script creates empty `~/IdeaProjects/by-agent` and `~/IdeaProjects/by-dev` directories. It does not configure Git identities or create organization specific directories. The agent directory receives an SELinux label suitable for container mounts.

## GNOME setup

Configure Dash to Dock:

```bash
./init_de.sh
```

Removing preinstalled games and LibreOffice is an explicit option:

```bash
./init_de.sh --remove-extra-apps
```

Skip this script on desktop environments other than GNOME.

## Swap examples

Create and enable a swap file inside the guest:

```bash
./setup_guest_swap.sh 8
```

The argument is any positive size in GiB. The script uses the Btrfs swapfile command on a Btrfs root filesystem and a regular swap file elsewhere. Fedora's zram may coexist with disk swap.

## Transfer a home directory

Install and enable OpenSSH Server and `rsync` inside the guest. Obtain its NAT address and verify its SSH host key through the VM console. From the host, preview the transfer:

```bash
./transfer_home.sh USER@GUEST_IP
```

Apply it only after reviewing the preview:

```bash
./transfer_home.sh USER@GUEST_IP --apply
```

SSH encrypts the transfer. The script copies most of the home directory, including Firefox profiles and `.gitconfig`, while excluding `Downloads`, caches, trash, desktop keyrings, SSH keys, GPG keys, PKI data, Firefox saved-login databases and selected application credentials. Close Firefox on both systems before copying, then verify bookmarks and profiles in the guest. The script never deletes source files. Delete host data only after verifying a separate backup and the copied data.

## Optional isolated Claude launcher

```bash
./init_claude.sh
```

This builds a Docker based launcher that exposes one selected project below `~/IdeaProjects/by-agent/<group>/<project>` to Claude. It uses the command name `claude`, so it replaces that command with the container launcher while installed.

## Files

- `create_vms.sh`: creates one VM from a local ISO.
- `init_guest_apps.sh`: guest integration and optional application groups.
- `setup_guest_swap.sh`: creates disk backed swap.
- `init_dev.sh`: Android and backend development profiles.
- `init_de.sh`: optional GNOME configuration and cleanup.
- `init_claude.sh`, `docker/claude/`: optional isolated Claude launcher.
- `transfer_home.sh`: previews and copies a home directory over SSH.

Personal instructions may be kept in `FORME.md`, which is ignored by Git.
