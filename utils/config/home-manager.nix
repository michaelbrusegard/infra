{ pkgs, specialArgs, userName, catppuccin, dotfiles-private, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${userName} = {
      imports = [
        dotfiles-private.homeModules.secrets
        catppuccin.homeModules.catppuccin
        ../../modules
        ../../users/${userName}
      ];
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
