{ pkgs, specialArgs, username, catppuccin, ... }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "backup";
    users.${username} = {
      imports = [
        catppuccin.homeManagerModules.catppuccin
        ../../modules
        ../../users/${username}
      ];
    };
    extraSpecialArgs = pkgs.lib.mkForce specialArgs;
  };
}
