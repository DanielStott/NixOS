#!/usr/bin/env bash
# Installs a minimal encrypted NixOS onto two partitions made beforehand (GPT labels
# NIXOS-ESP and NIXOS-CRYPT). Nothing else on the machine is touched. At the first login
# it signs in to GitHub, fetches your private flake and installs that.
#
# From the NixOS installer (the minimal, console one), online, in a copy of this repo:
#   sudo bash install/install.sh
# Any question can be answered ahead with an environment variable of the same name
# (USERNAME, HOST, PRIVATE_REPO, APP_CLIENT_ID, KEYMAP, TIMEZONE).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
ESP=/dev/disk/by-partlabel/NIXOS-ESP
CRYPT=/dev/disk/by-partlabel/NIXOS-CRYPT
MAPPER=cryptnixos

fail() { printf '\nSTOPPED: %s\n' "$*" >&2; exit 1; }
say()  { printf '\n== %s\n' "$*"; }
# ask VAR "question" [default] [pattern]
ask() {
  local var=$1 question=$2 default=${3:-} pattern=${4:-.} value
  value="${!var:-}"
  if [ -z "$value" ]; then
    read -r -p "$question${default:+ [$default]}: " value
    value="${value:-$default}"
  fi
  [ -n "$value" ] || fail "$question: an answer is needed"
  [[ "$value" =~ $pattern ]] || fail "$question: '$value' doesn't look right"
  printf -v "$var" '%s' "$value"
}

[ "$(id -u)" -eq 0 ] || fail "run it with sudo"
[ -f "$here/flake.nix" ] && [ -f "$here/modules/system.nix" ] || fail "run it from a copy of the repo (install/install.sh)"
[ -b "$ESP" ] && [ -b "$CRYPT" ] || fail "can't find the NIXOS-ESP and NIXOS-CRYPT partitions"
esp_dev="$(readlink -f "$ESP")"; crypt_dev="$(readlink -f "$CRYPT")"
disk="/dev/$(lsblk -no PKNAME "$crypt_dev")"
[ "/dev/$(lsblk -no PKNAME "$esp_dev")" = "$disk" ] || fail "the two partitions are on different drives"

say "About this machine"
ask USERNAME "Your login name" "" '^[a-z_][a-z0-9_-]{0,31}$'
ask HOST "This machine's name in your private flake (nixosConfigurations.<name>)" "" '^[A-Za-z0-9-]{1,63}$'
ask PRIVATE_REPO "Your private flake on GitHub (owner/name)" "" '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$'
ask APP_CLIENT_ID "Your GitHub App's client ID (for the sign-in at first login)" "" '^[A-Za-z0-9.]{8,64}$'
ask KEYMAP "Keyboard layout (console and disk passphrase)" "us" '^[A-Za-z0-9_-]+$'
ask TIMEZONE "Time zone" "UTC" '^[A-Za-z0-9/_+-]+$'
[ -e "/etc/zoneinfo/$TIMEZONE" ] || fail "no time zone called $TIMEZONE"
# Type the passphrase in the layout the boot prompt will use.
loadkeys "$KEYMAP" >/dev/null 2>&1 || fail "no keyboard layout called $KEYMAP"
echo "Keyboard set to $KEYMAP. (In a graphical installer, set the same layout in its settings.)"

model="$(lsblk -dno MODEL "$disk")"
say "About to format, on $disk ($model):"
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL "$disk"
cat <<EOF

  $esp_dev  NIXOS-ESP    -> new FAT32 boot partition
  $crypt_dev  NIXOS-CRYPT  -> new LUKS2 (you choose the passphrase) with Btrfs inside
  Nothing else is touched.
EOF
existing="$(blkid -o value -s TYPE "$esp_dev" "$crypt_dev" 2>/dev/null | tr '\n' ' ')"
[ -z "$existing" ] || echo "  Note: these partitions already hold: $existing(they will be overwritten)"
read -r -p $'\nType "install" to continue: ' answer
[ "$answer" = "install" ] || fail "cancelled; nothing changed"

say "Formatting the boot partition"
mkfs.vfat -F 32 -n NIXOS-ESP "$esp_dev"

say "Encrypting NIXOS-CRYPT (choose the passphrase you'll type at every start)"
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
btrfs subvolume create /mnt/home/.snapshots # for snapper, if your config uses it

say "Writing the config to /etc/nixos"
mkdir -p /mnt/etc/nixos
cp -r "$here/flake.nix" "$here/flake.lock" "$here/machine.example.nix" "$here/modules" /mnt/etc/nixos/
nixos-generate-config --root /mnt --no-filesystems --show-hardware-config > /mnt/etc/nixos/hardware.nix
cat > /mnt/etc/nixos/machine.nix <<EOF
{
  user = "$USERNAME";
  hostName = "$HOST";
  privateRepo = "$PRIVATE_REPO";
  githubAppClientId = "$APP_CLIENT_ID";
  keyMap = "$KEYMAP";
  timeZone = "$TIMEZONE";
}
EOF

say "Installing (this downloads a few hundred MB)"
nixos-install --root /mnt --flake /mnt/etc/nixos#installed --no-root-passwd \
  --option extra-experimental-features "nix-command flakes"

say "Set the password for $USERNAME (for logging in and sudo)"
nixos-enter --root /mnt -c "passwd $USERNAME"

say "Done"
cat <<EOF
Restart and remove the installer stick. Unlock the disk, then log in as $USERNAME on
the console: the first-login steps start by themselves (GitHub sign-in on your phone,
then your private config, then a restart into it).
EOF
