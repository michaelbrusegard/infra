{
  inputs,
  config,
  ...
}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    enable = true;
    accent = "blue";
    flavor = "mocha";

    mpv.enable = false;
    gh-dash.enable = false;
    fzf.enable = !config._module.check;
  };
}
