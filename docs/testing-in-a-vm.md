# Testing in a VM

Try desktop changes in QEMU before installing them on the laptop.

## Build and run

```sh
# Build the live ISO of the VM variant (same modules as `precision`, no laptop disk layout)
podman run --rm -v nixcheck-store:/nix -v "$PWD":/src:Z -w /src docker.io/nixos/nix \
  nix --extra-experimental-features 'nix-command flakes' --option accept-flake-config true \
  build --print-out-paths .#nixosConfigurations.precision-vm.config.system.build.images.iso
# The output path is a folder; the .iso is inside it.

qemu-img create -f qcow2 scratch.qcow2 20G
tools/run-vm.sh scratch.qcow2 path/to/the.iso     # needs qemu-system-x86 and ovmf
```

The test password is `nixos`. The VM boots from the ISO, so nothing persists between runs.
Inside the VM, the host is at 10.0.2.2; the host reaches the VM's SSH on 127.0.0.1:2222
(key-only, with the VM-only key in hosts/precision-vm). Boot messages go to
`scratch.serial.log` next to the disk.

## What the first runs found (2026-11-06)

- **The lock screen looked like a dead boot.** hyprlock's background was a blurred screenshot
  (black at boot) and the password box hid until typing. Now: solid colour, clock, date and an
  always-visible box.
- **Noctalia's first-run wizard took the keyboard from the lock screen**, so the password went
  nowhere. Settings are declared in Nix, so `shell.setup_wizard_enabled = false`.
- **Hyprland reads a leading `[...]` in an exec command as window rules**, so
  `[ -e file ] || cmd` silently never ran. Use `test -e file || cmd`.
- **QEMU display on a COSMIC (Wayland) host:** QEMU 8.2's GTK window with `gl=on` never showed
  frames, and SDL as a native Wayland client never passed keystrokes to the guest. SDL through
  XWayland (`SDL_VIDEODRIVER=x11`) works; `run-vm.sh` does this by default.
- **The qcow2 image builder ran out of memory** copying a desktop-sized system; the ISO
  (squashfs) route doesn't have that limit. ISOs need `isoImage.makeEfiBootable = true` to boot
  under UEFI.
- **QEMU's `screendump` can't capture a virgl display** ("no surface"); take screenshots
  inside the guest with `grim` over SSH instead.

## Envs (2026-11-06)

The VM defines two test envs, `demo` (internet only) and `demo2` (LAN on). The isolation
checks (protocols, internet, LAN, host, other env, Nix daemon) pass; GPU rendering inside
an env uses the VM's virgl GPU through dmabuf.

- **A tagging Wayland proxy (wayland-proxy-virtwl) forces software rendering**: it doesn't
  pass GPU buffers through, so Mesa inside the env falls back to llvmpipe. Envs now connect
  to Hyprland directly through a `wp_security_context_v1` socket (`pkgs/env-wayland-socket`),
  which keeps dmabuf while Hyprland withholds its privileged protocols (its allow-list is in
  `src/managers/ProtocolManager.cpp`). Windows are tagged by the client's cgroup instead of a
  title prefix.
- **A fixed `privateUsers` UID base needs `--private-users-ownership=auto`**; only `pick` gets
  it by default. Without it the env's root can't write its own `/etc` and boot fails.
- **Bind mounts use `:idmap`** (appended to the mount point), so host-owned folders appear as
  the env user's own; no chown of shared data.
- **`systemd-run --user` in a container doesn't search PATH for bare names**, so `env-launch`
  runs commands through the env's `bash -l`.
- **nftables needs `ve-*`**: `networking.nat.internalInterfaces = [ "ve-+" ]` (iptables syntax)
  is written literally and matches nothing, so envs had no internet.
