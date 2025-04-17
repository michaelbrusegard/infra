{ pkgs, specialArgs, userName, sops-nix, catppuccin, secrets, isDarwin, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${userName} = {
      imports = [
        sops-nix.homeManagerModules.sops
        catppuccin.homeModules.catppuccin
        ../../modules
        ../../users/${userName}
      ];
      sops = {
        age.keyFile = if isDarwin 
          then "/Users/${userName}/.config/sops/age/keys.txt"
          else "/home/${userName}/.config/sops/age/keys.txt";
        defaultSopsFile = "${builtins.toString secrets}/secrets.yaml";
      };
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
