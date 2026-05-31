{
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];
  catppuccin = {
    enable = true;
    autoEnable = true;
    accent = "blue";
    flavor = "mocha";
    hyprland.enable = false;
    opencode.enable = false;
    mpv.enable = false;
    gh-dash.enable = false;
    fzf.enable = !config._module.check;
  };
}
