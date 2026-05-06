{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-index-database.homeModules.default
  ];

  programs = {
    nix-index = {
      enable = true;
      enableZshIntegration = true;
    };
    nix-index-database.comma.enable = true;
  };

  home.packages = with pkgs; [
    colmena
    nixos-anywhere
    nix-output-monitor
    nvd
  ];
}
