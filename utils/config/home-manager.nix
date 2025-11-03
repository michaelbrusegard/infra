{ pkgs, specialArgs, userName, catppuccin, dotfiles-private, mac-app-util, dankMaterialShell, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${userName} = {
      imports = [
        dotfiles-private.homeModules.secrets
        catppuccin.homeModules.catppuccin
        mac-app-util.homeManagerModules.default
        dankMaterialShell.homeModules.dankMaterialShell.default
        ../../modules
        ../../users/${userName}
      ];
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
