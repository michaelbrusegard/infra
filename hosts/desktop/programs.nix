{ userName, dankMaterialShell, ... }: {
  imports = [
    dankMaterialShell.nixosModules.greeter
  ];
  programs = {
    ssh.startAgent = true;
    dconf.enable = true;
    hyprland = {
      enable = true;
      withUWSM = true;
    };
    dankMaterialShell.greeter = {
      enable = true;
      compositor.name = "hyprland";
      configHome = "/home/${userName}";
    };
  };
}
