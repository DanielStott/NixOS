# NixOS

NixOS for a Dell Precision 7680 (i7-13850HX, Intel iGPU + NVIDIA RTX 2000 Ada), dual-booted
next to Pop!_OS. This public flake builds a complete base system that installs from anywhere
with no login. A separate private flake layers the real environments, hosts and secrets on
top of it.

## What the base gives you

- **Disk:** NixOS on its own partitions of the second NVMe, found by GPT label:
  `NIXOS-ESP` (1 GiB, `/boot`) and `NIXOS-CRYPT` (LUKS2 with a passphrase at boot,
  holding Btrfs subvolumes `@root`, `@home`, `@nix`, `@log`). Pop!_OS stays untouched.
- **Desktop:** Hyprland 0.55 with its Lua config, the [Noctalia](https://github.com/noctalia-dev/noctalia)
  shell, hyprlock and hypridle. After the disk passphrase it logs straight in and locks,
  so the user password unlocks the screen.
- **Graphics:** the Intel iGPU only. NVIDIA's driver doesn't build against the 7.x kernels
  yet, so the RTX is taken off the PCI bus at boot to save power (`nvidia-off.nix`).
  `nvidia-prime.nix` (PRIME offload with `nvidia-offload <app>`) is ready for when it does.
- **System:** latest stable kernel, NixOS 26.05 with nixpkgs-unstable available for
  fast-moving tools, zram swap, hourly snapper snapshots of `/home`, PipeWire,
  NetworkManager, UK keyboard and en_GB locale, zsh with oh-my-zsh, Ghostty.

## Keys

| Keys | Does |
|---|---|
| Super+T | Terminal (Ghostty) |
| Super+E | Files (Nautilus) |
| Super+Space | Launcher |
| Super+S | Control centre |
| Super+, | Noctalia settings |
| Alt+Tab | Window switcher |
| Super+Q | Close window |
| Super+F / Super+V | Fullscreen / float |
| Super+1..0, Super+Shift+1..0 | Go to / move window to workspace |
| Super+L | Lock |
| Print, Shift+Print | Screenshot a region / the screen to `~/Pictures/Screenshots` |

## Install

1. Boot the NixOS installer (any recent ISO) with internet.
2. Run:
   ```sh
   curl -LO https://raw.githubusercontent.com/DanielStott/NixOS/main/install/install.sh
   sudo bash install.sh
   ```
   It only formats the `NIXOS-ESP` and `NIXOS-CRYPT` partitions, after checking they are on
   the expected drive and asking you to type `install`.
3. Reboot. NixOS starts by default; press F12 at the Dell logo to pick Pop!_OS.

## First login

A terminal opens once with `nixos-finish-setup`, which:

1. signs in with the owner's own GitHub App (device flow: scan the QR code and approve the
   code on your phone). The App is installed on the private repo only, so the
   short-lived token it gets, kept in memory only, can't reach anything else;
2. uses it to add a read-only deploy key for the private repo, and clones that repo to
   `/etc/nixos-private` (root-owned, so no env can edit the config);
3. asks for the age key if the private repo holds sops secrets;
4. switches to the private flake.

Afterwards, `nixos-update` pulls the private repo and rebuilds from it.

## Layout

```
flake.nix                    inputs, the `precision` system, reusable modules
hosts/precision/             host settings and hardware (partitions, PRIME bus IDs)
modules/nixos/               base, desktop, nvidia-prime, snapshots
modules/home/                Home Manager: Hyprland Lua config, Noctalia, lock/idle, shell
install/install.sh           formats the two NixOS partitions and runs nixos-install
```

## Checking changes without installing

Evaluate and build in a Nix container (no Nix needed on the host):

```sh
podman run --rm -v nixcheck-store:/nix -v "$PWD":/src:Z -w /src docker.io/nixos/nix \
  nix --extra-experimental-features 'nix-command flakes' --option accept-flake-config true \
  build --no-link .#nixosConfigurations.precision.config.system.build.toplevel
```
