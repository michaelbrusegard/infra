{inputs, ...}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    (
      {
        config,
        lib,
        pkgs,
        options,
        ...
      } @ args:
        builtins.removeAttrs
        (import "${inputs.nixpkgs-unstable}/nixos/modules/programs/dsearch.nix" args)
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
