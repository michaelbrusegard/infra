{ pkgs, specialArgs, userName, catppuccin, dotfiles-private, dankMaterialShell, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${userName} = {
      imports = [
        dotfiles-private.homeModules.secrets
        catppuccin.homeModules.catppuccin
        dankMaterialShell.homeModules.dankMaterialShell.default
        ../../modules
        ../../users/${userName}
      ];
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
