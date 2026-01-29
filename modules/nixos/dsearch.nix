{inputs, ...}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/programs/dsearch.nix"
  ];

  programs.dsearch = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
  };
}
