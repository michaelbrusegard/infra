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
    fzf.enable = !config._module.check;
    zsh.enable = !config._module.check;
    bat.enable = !config._module.check;
  };
}
