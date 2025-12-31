{ lib, isWsl, ... }:

{
  programs.zathura = lib.mkIf (!isWsl) {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
    };
  };
}
