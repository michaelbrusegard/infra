{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
in {
  # libvncclient is the only VNC backend packaged here that implements Apple
  # Remote Desktop auth, which is what lungo requires.
  home =
    {
      packages = lib.mkIf enable [pkgs.remmina];
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".config/remmina"
        ".local/share/remmina"
      ];
    };

  # `relax_encryption` is what makes wayvnc advertise Apple Diffie-Hellman, the
  # only security type macOS Screen Sharing understands here. `enable_pam`
  # authenticates against the login password, so there is no secret to manage.
  xdg.configFile."wayvnc/config" = lib.mkIf enable {
    text = ''
      address=0.0.0.0
      enable_auth=true
      enable_pam=true
      relax_encryption=true
      xkb_layout=us
    '';
  };

  # Resizing is disabled because wayvnc answers a client window resize by
  # changing the captured output's mode, physical outputs included.
  systemd.user.services.wayvnc = lib.mkIf enable {
    Unit = {
      Description = "VNC server for the Hyprland session";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.wayvnc} --disable-resizing";
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
