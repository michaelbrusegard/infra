{ pkgs, specialArgs, username, sops-nix, catppuccin, secrets, isDarwin, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${username} = {
      imports = [
        sops-nix.homeManagerModules.sops
        catppuccin.homeManagerModules.catppuccin
        ../../modules
        ../../users/${username}
      ];
      sops = {
        age.keyFile = if isDarwin 
          then "/Users/${username}/.config/sops/age/keys.txt"
          else "/home/${username}/.config/sops/age/keys.txt";
        defaultSopsFile = "${builtins.toString secrets}/secrets.yaml";
        validateSopsFile = false;
      };
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
