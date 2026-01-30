{
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.catppuccin.nixosModules.catppuccin
  ];
  catppuccin = {
    enable = true;
    accent = "blue";
    flavor = "mocha";
    gtk.enable = false;
    cache.enable = true;
    tty.enable = !config._module.check;
  };
}
