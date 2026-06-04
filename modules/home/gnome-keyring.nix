{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  # Secret Service provider for the graphical session. The dms/greetd
  # greeter does not run pam_gnome_keyring, so the login keyring relies
  # on an empty password for unattended unlock.
  services.gnome-keyring = lib.mkIf (!isWsl && pkgs.stdenv.isLinux) {
    enable = true;
    components = ["secrets"];
  };

  home = lib.optionalAttrs (homePersistenceRoot != null) {
    persistence.${homePersistenceRoot}.directories = [
      ".local/share/keyrings"
    ];
  };
}
