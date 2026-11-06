# Hourly Btrfs snapshots of /home for quick undo (the weekly off-laptop backup is
# separate). The /home/.snapshots subvolume is created by the install script.
{ ... }:
{
  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "stott" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 24;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 3;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };
}
