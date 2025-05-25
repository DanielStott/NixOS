{ disk ? "", ... }: {
  disko.devices = {
    disk = {
      vdb = {
        type = "disk";
        device = "/dev/${disk}";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "2048M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              name = "cryptroot";
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  allowDiscards = true;
                  keyFile = null;
                };
                content = {
                  type = "filesystem";
                  format = "btrfs";
                  mountpoint = "/";
                  subvolumes = {
                    "/root" = { mountpoint = "/"; };
                    "/home" = { mountpoint = "/home"; };
                    "/nix" = { mountpoint = "/nix"; };
                    "/var" = { mountpoint = "/var"; };
                    "/@snapshots" = { mountpoint = "/.snapshots"; };
                  };
                  options = [
                    "compress=zstd"
                    "noatime"
                    "space_cache=v2"
                    "ssd"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}