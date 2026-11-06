#!/usr/bin/env bash
# Install this flake's `precision` system next to Pop!_OS, onto the two partitions made
# for it on the Samsung 980 (GPT labels NIXOS-ESP and NIXOS-CRYPT). Nothing else is
# touched: not Pop!_OS's drive, not the shared data partition.
#
# From the NixOS installer, with internet:
#   curl -LO https://raw.githubusercontent.com/DanielStott/NixOS/main/install/install.sh
#   sudo bash install.sh
# (Download it first rather than piping it into bash: it asks for the disk passphrase.)
set -euo pipefail

FLAKE="${FLAKE:-github:DanielStott/NixOS#precision}"
ESP=/dev/disk/by-partlabel/NIXOS-ESP
CRYPT=/dev/disk/by-partlabel/NIXOS-CRYPT
MAPPER=cryptnixos

fail() { printf '\nSTOPPED: %s\n' "$*" >&2; exit 1; }
say()  { printf '\n== %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || fail "run it with sudo"
[ -b "$ESP" ] && [ -b "$CRYPT" ] || fail "can't find the NIXOS-ESP and NIXOS-CRYPT partitions"

esp_dev="$(readlink -f "$ESP")"; crypt_dev="$(readlink -f "$CRYPT")"
disk="/dev/$(lsblk -no PKNAME "$crypt_dev")"
[ "/dev/$(lsblk -no PKNAME "$esp_dev")" = "$disk" ] || fail "the two partitions are on different drives"
model="$(lsblk -dno MODEL "$disk")"
if [ "${ALLOW_ANY_DISK:-}" = "1" ]; then
  echo "ALLOW_ANY_DISK=1: skipping the Samsung 980 check (VM rehearsal only)."
else
  case "$model" in *"Samsung SSD 980"*) ;; *) fail "the partitions are on '$model', not the Samsung 980";; esac
fi

say "About to format, on $disk ($model):"
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL "$disk"
cat <<EOF

  $esp_dev  NIXOS-ESP    -> new FAT32 boot partition
  $crypt_dev  NIXOS-CRYPT  -> new LUKS2 (you choose the passphrase) with Btrfs inside
  Partition 1 (shared data) and the other drive are not touched.
EOF
existing="$(blkid -o value -s TYPE "$esp_dev" "$crypt_dev" 2>/dev/null | tr '\n' ' ')"
[ -z "$existing" ] || echo "  Note: these partitions already hold: $existing(they will be overwritten)"
read -r -p $'\nType "install" to continue: ' answer
[ "$answer" = "install" ] || fail "cancelled; nothing changed"

say "Formatting the boot partition"
mkfs.vfat -F 32 -n NIXOS-ESP "$esp_dev"

say "Encrypting NIXOS-CRYPT (choose the passphrase you'll type at every boot)"
cryptsetup luksFormat --type luks2 "$crypt_dev"
cryptsetup open "$crypt_dev" "$MAPPER"

say "Creating Btrfs subvolumes"
mkfs.btrfs -f -L nixos "/dev/mapper/$MAPPER"
mount -o subvolid=5 "/dev/mapper/$MAPPER" /mnt
for sv in @root @home @nix @log; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

opts="compress=zstd,noatime"
mount -o "subvol=@root,$opts" "/dev/mapper/$MAPPER" /mnt
mkdir -p /mnt/home /mnt/nix /mnt/var/log /mnt/boot
mount -o "subvol=@home,$opts" "/dev/mapper/$MAPPER" /mnt/home
mount -o "subvol=@nix,$opts"  "/dev/mapper/$MAPPER" /mnt/nix
mount -o "subvol=@log,$opts"  "/dev/mapper/$MAPPER" /mnt/var/log
mount -o fmask=0077,dmask=0077 "$esp_dev" /mnt/boot
btrfs subvolume create /mnt/home/.snapshots   # used by the hourly snapper snapshots

say "Saving what the installer detects, for comparison with hosts/precision/hardware.nix"
mkdir -p /mnt/etc/nixos
nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware-detected.nix 2>/dev/null || true

say "Installing $FLAKE (this downloads a few GB)"
nixos-install --root /mnt --flake "$FLAKE" --no-root-passwd \
  --option extra-experimental-features "nix-command flakes" \
  --option accept-flake-config true

say "Set the password for stott (used to unlock the screen and for sudo)"
nixos-enter --root /mnt -c 'passwd stott'

say "Done"
cat <<EOF
Reboot and remove the installer stick. The laptop now starts NixOS by default
(it asks for the disk passphrase, then opens Hyprland locked: unlock with stott's password).
To start Pop!_OS instead, press F12 at the Dell logo and pick the SK hynix drive.
EOF
