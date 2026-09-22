{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
in {
  # Remmina's VNC plugin is libvncclient, the only client packaged here that
  # implements Apple Remote Desktop auth, so it is what reaches lungo. macOS
  # connects the other way with its built-in Screen Sharing.app and needs
  # nothing installed.
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

  # Bind on every interface and let the firewall confine this to NetBird: the
  # NetBird address only exists once the tunnel is up, which races the
  # graphical session this unit belongs to.
  #
  # `enable_pam` authenticates against the user's login password, so there is
  # no key material or secret to manage. `relax_encryption` is what makes
  # wayvnc advertise Apple Diffie-Hellman next to RSA-AES; without it macOS
  # Screen Sharing finds no security type it understands and gives up.
  #
  # wayvnc hands its own keymap to the virtual keyboard it creates, so the xkb
  # settings have to match the session in `modules/home/hyprland.nix` or remote
  # keystrokes produce the wrong characters.
  xdg.configFile."wayvnc/config" = lib.mkIf enable {
    text = ''
      address=0.0.0.0
      enable_auth=true
      enable_pam=true
      relax_encryption=true
      xkb_variant=mac
      xkb_options=lv3:lalt_switch
    '';
  };

  # wayvnc attaches to a running compositor, so it lives and dies with the
  # session. hyprlock renders over VNC and can be unlocked remotely; the
  # greeter cannot, because no session exists yet.
  systemd.user.services.wayvnc = lib.mkIf enable {
    Unit = {
      Description = "VNC server for the Hyprland session";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      ExecStart = lib.getExe pkgs.wayvnc;
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
