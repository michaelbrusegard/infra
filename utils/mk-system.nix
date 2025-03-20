inputs:
{ system, username, hostname }:
let
  isDarwin = builtins.match ".*-darwin" system != null;

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit system username hostname isDarwin;
      inherit (inputs) nixpkgs;
    };
  };

in
  if isDarwin then
    inputs.darwin.lib.darwinSystem (commonArgs // {
      modules = [];
    })
  else
    inputs.nixpkgs.lib.nixosSystem (commonArgs // {
      modules = [
        {
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          system.stateVersion = "24.11";
        }
      ];
    })
