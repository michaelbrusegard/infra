{
  flake.modules.homeManager.gnome-keyring =
    {
      pkgs,
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    let
      components = [ "secrets" ];
      # `gnome-keyring-daemon --unlock` always starts a daemon of its own instead of
      # unlocking one that is running, so unlocking after the service starts leaves
      # a second daemon behind and the login keyring that clients use locked. The
      # service's daemon reads the empty login password itself as it starts.
      unlockedDaemon = pkgs.writeShellScript "gnome-keyring-unlocked" ''
        printf '\n' | exec ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon \
          --foreground --components=${lib.concatStringsSep "," components} --unlock
      '';
    in
    {
      services.gnome-keyring = {
        enable = true;
        inherit components;
      };

      systemd.user.services.gnome-keyring = {
        Service.ExecStart = lib.mkForce "${unlockedDaemon}";
      };

      home = lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = [
          ".local/share/keyrings"
        ];
      };
    };
}
