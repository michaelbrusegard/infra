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
    accent = "blue";
    flavor = "mocha";
    opencode.enable = false;
    mpv.enable = false;
    gh-dash.enable = false;
    fzf.enable = !config._module.check;
  };
}
