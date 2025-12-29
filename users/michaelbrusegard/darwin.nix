{ pkgs, ... }:

{
  users.users.michaelbrusegard = {
    home = "/Users/michaelbrusegard";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;
}
