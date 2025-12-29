inputs:

{ hostname, system, users }:

let
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = inputs.self.overlays.default;
  };
in
inputs.nixpkgs.lib.nixosSystem {
  inherit system pkgs;

  specialArgs = {
    inherit inputs hostname users;
    isWsl = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  };

  modules =
    [ ../hosts/${hostname} ]
    ++ map
      (u: ../../users/${u}/nixos.nix)
      users;
}
