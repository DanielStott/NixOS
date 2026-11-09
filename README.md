# NixOS installer

Installs a minimal NixOS on an encrypted disk, then hands over to your own private flake at
the first login. This repo holds only that first step; everything else lives in the
private flake.

## Before you start

- **Two partitions** on the target drive, made with any partitioning tool, with these GPT
  labels: `NIXOS-ESP` (about 1 GiB) and `NIXOS-CRYPT` (the rest). Both are formatted;
  nothing else on the machine is touched.
- **A private flake on GitHub** with a `nixosConfigurations.<name>` for this machine. It
  should keep the disk layout made here: LUKS on `NIXOS-CRYPT` opened as `cryptnixos`,
  Btrfs subvolumes `@root`, `@home`, `@nix`, `@log`, and `NIXOS-ESP` at `/boot`.
- **A GitHub App** for the first sign-in: device flow enabled, the Administration
  permission (read and write), installed on the private repo only. You'll need its
  client ID.

## Install

1. Boot the NixOS installer (the minimal one) and get online (`nmtui` for Wi-Fi).
2. Get a copy of this repo (`git clone`, or download and unpack its archive).
3. Run `sudo bash install/install.sh` from the copy and answer its questions: your login
   name, the machine's name in your flake, the private repo, the App's client ID, your
   keyboard layout and time zone.
4. Restart and remove the installer stick.

## First login

Unlock the disk and log in on the console. `nixos-finish-setup` starts by itself:

1. shows a code (and a QR code for the page) to approve on your phone with your App;
2. uses that short-lived token, in memory only, to add a read-only deploy key to the
   private repo;
3. clones the private repo to `/etc/nixos-private` (readable by root only);
4. installs its `nixosConfigurations.<name>` and restarts into it.
