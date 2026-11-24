{inputs, ...}: {
  hosts.lungo = {
    system = "aarch64-darwin";
    users = ["michaelbrusegard"];
  };

  flake.modules.darwin.lungo = {
    imports = with inputs.self.modules.darwin; [
      aerospace
      fonts
      home-manager
      homebrew
      jankyborders
      kanata
      localsend
      networking
      nh
      nix
      openssh
      security
      system
      tailscale
      virtualisation
      wallpaper
    ];

    time.timeZone = "America/Los_Angeles";

    system.stateVersion = 5;
  };
}
