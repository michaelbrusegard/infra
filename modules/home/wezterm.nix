{
  config,
  inputs,
  ...
}: let
  weztermConfig = inputs.self + "/config/wezterm";
in {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };

  xdg.configFile."wezterm".source =
    config.lib.file.mkOutOfStoreSymlink weztermConfig;
}
