{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.browser;

in {
  options.modules.browser.enable = lib.mkEnableOption "Browser configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      chromium = lib.mkIf (!isDarwin) {
        enable = true;
        package = pkgs.vivaldi;
      };
      qutebrowser = {
        enable = true;
      };
    };
  };
}
