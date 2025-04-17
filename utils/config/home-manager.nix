{ pkgs, specialArgs, userName, sops-nix, catppuccin, dotfiles-private, isDarwin, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${userName} = {
      imports = [
        dotfiles-private.homeModules.secrets
        sops-nix.homeManagerModules.sops
        catppuccin.homeModules.catppuccin
        ../../modules
        ../../users/${userName}
      ];
      sops = {
        age.keyFile = if isDarwin 
          then "/Users/${userName}/.config/sops/age/keys.txt"
          else "/home/${userName}/.config/sops/age/keys.txt";
        defaultSopsFile = "${builtins.toString dotfiles-private}/secrets.yaml";
      };
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
