{ inputs, ... }: {
  flake.modules.nixos.catppuccin = { config, ... }: {
    imports = [
      inputs.catppuccin.nixosModules.catppuccin
    ];
    catppuccin = {
      enable = true;
      autoEnable = true;
      accent = "blue";
      flavor = "mocha";
      cache.enable = true;
      tty.enable = !config._module.check;
      # autoEnable would turn this on for every host, but the integration
      # writes services.home-assistant.config unconditionally; our HA hosts
      # manage config via the UI (config = null), so keep it off globally.
      home-assistant.enable = false;
    };
  };

  flake.modules.homeManager.catppuccin = { config, ... }: {
    imports = [
      inputs.catppuccin.homeModules.catppuccin
    ];
    catppuccin = {
      enable = true;
      autoEnable = true;
      accent = "blue";
      flavor = "mocha";
      hyprland.enable = false;
      mpv.enable = false;
      gh-dash.enable = false;
      fzf.enable = !config._module.check;
    };
  };
}
