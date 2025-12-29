{ pkgs, lib, ... }:

let
  weztermDarwin =
    pkgs.runCommand "wezterm-homebrew-wrapper" { } ''
      mkdir -p $out/bin
      ln -s /opt/homebrew/bin/wezterm $out/bin/wezterm
    '';

  weztermConfig = ../../config/wezterm;
in
{
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;

    package =
      if pkgs.stdenv.isDarwin then weztermDarwin else pkgs.wezterm;
  };

  xdg.configFile."wezterm".source =
    lib.file.mkOutOfStoreSymlink weztermConfig;
}
