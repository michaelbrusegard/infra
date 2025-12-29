{ pkgs, ... }:

let
  zathuraDarwin =
    pkgs.runCommand "zathura-homebrew-wrapper" { } ''
      mkdir -p $out/bin
      ln -s /opt/homebrew/bin/zathura $out/bin/zathura
    '';
in
{
  programs.zathura = {
    enable = true;

    package =
      if pkgs.stdenv.isDarwin then zathuraDarwin else pkgs.zathura;

    options = {
      selection-clipboard = "clipboard";
    };
  };
}
