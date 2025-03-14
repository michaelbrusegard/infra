{ pkgs, username, userPath, catppuccin }:
{
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    users.${username} = {
      imports = [
        catppuccin.homeManagerModules.catppuccin
        userPath
      ];
    };
  };
}
