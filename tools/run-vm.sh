#!/usr/bin/env bash
# Run a NixOS test VM with UEFI, KVM and 3D acceleration (virgl on the host's GPU).
# Needs Ubuntu/Pop!_OS packages qemu-system-x86 and ovmf.
#   tools/run-vm.sh DISK.qcow2               boot an existing disk
#   tools/run-vm.sh DISK.qcow2 INSTALLER.iso boot the installer with the disk attached
# Inside the VM the host is reachable at 10.0.2.2.
set -euo pipefail

disk="${1:?usage: run-vm.sh DISK.qcow2 [INSTALLER.iso]}"
iso="${2:-}"
code=/usr/share/OVMF/OVMF_CODE_4M.fd
vars="${disk%.*}.OVMF_VARS.fd"
[ -e "$vars" ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"

args=(
  -name "NixOS test" -enable-kvm -machine q35 -cpu host -smp 4 -m "${VM_MEM:-8G}"
  -drive "if=pflash,format=raw,readonly=on,file=$code"
  -drive "if=pflash,format=raw,file=$vars"
  -drive "file=$disk,if=virtio,format=qcow2"
  # VM_DISPLAY=egl-headless renders on the host GPU with no window (screenshots: grim in the
  # guest over SSH). SDL by default: QEMU 8.2's GTK window with gl=on never showed frames under COSMIC.
  -device virtio-vga-gl -display "${VM_DISPLAY:-sdl,gl=on}"
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
  -serial "file:${disk%.*}.serial.log"
  -device qemu-xhci -device usb-tablet
  # Control socket next to the disk, e.g. for screenshots of the VM alone:
  #   echo 'screendump /tmp/vm.ppm' | socat - UNIX-CONNECT:DISK.monitor.sock
  -monitor "unix:${disk%.*}.monitor.sock,server,nowait"
)
[ -n "$iso" ] && args+=(-cdrom "$iso")
# SDL as a native Wayland client under COSMIC never passed keystrokes to the guest
# (the mouse worked); through XWayland it does.
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
exec qemu-system-x86_64 "${args[@]}"
