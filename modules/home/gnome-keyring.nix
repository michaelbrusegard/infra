{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  enable = !isWsl && pkgs.stdenv.hostPlatform.isLinux;
  unlockWrapper = pkgs.writeShellScript "gnome-keyring-empty-unlock" ''
    printf '\n' | exec ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock
  '';
in {
  services.gnome-keyring = lib.mkIf enable {
    enable = true;
    components = ["secrets"];
  };

  systemd.user.services.gnome-keyring = lib.mkIf enable {
    Service.ExecStartPost = unlockWrapper;
  };

  home = lib.optionalAttrs (homePersistenceRoot != null) {
    persistence.${homePersistenceRoot}.directories = [
      ".local/share/keyrings"
    ];
  };
}
