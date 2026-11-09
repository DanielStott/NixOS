# What install.sh asks for. It writes your answers to machine.nix on the new system; this
# file is only the example the repo builds with.
{
  user = "user"; # your login name
  hostName = "laptop"; # this machine's nixosConfigurations name in your private flake
  privateRepo = "owner/nixos-config"; # your private flake on GitHub
  githubAppClientId = "Iv23li0000000000000"; # your GitHub App's client ID (not a secret)
  keyMap = "us"; # console keyboard, also used for the disk passphrase at boot
  timeZone = "UTC";
}
