{
  flake.modules.nixos.localsend = {
    programs.localsend = {
      enable = true;
      openFirewall = true;
    };
  };

  flake.modules.darwin.localsend = {pkgs, ...}: {
    environment.systemPackages = [pkgs.localsend];
  };
}
