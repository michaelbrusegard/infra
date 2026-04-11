{inputs, ...}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
        builtins.removeAttrs
        (import "${inputs.nixpkgs-unstable}/nixos/modules/programs/dsearch.nix" {inherit config lib pkgs;})
        ["meta"]
    )
  ];

  programs.dsearch = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
  };
}
