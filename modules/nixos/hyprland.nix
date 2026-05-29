{lib, ...}: {
  options.local.hyprland.monitors = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
  };

  config = {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };
  };
}
