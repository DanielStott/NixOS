# precision-vm plus an "apps" env holding the heavy desktop apps the real envs use, to check
# they start and render inside an env (Chromium/Electron sandboxes, JetBrains on Wayland,
# Godot through the env's Xwayland, Blender on the GPU). Bigger ISO; only for app checks.
{ pkgs, pkgs-unstable, ... }:
{
  imports = [ ../precision-vm ];

  envs.apps = {
    id = 11;
    label = "Apps";
    color = "rgb(cba6f7)";
    packages = (with pkgs; [ google-chrome vivaldi discord obsidian godot_4_6-mono blender ])
      ++ (with pkgs-unstable; [ jetbrains.rider claude-code ]);
  };
}
