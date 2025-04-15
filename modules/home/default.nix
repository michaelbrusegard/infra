{ lib, config, pkgs, hostName, isDarwin, ... }:
{
  home = {
    stateVersion = "25.05";
    pointerCursor = lib.mkIf (config.modules.gui.enable && !isDarwin) {
      package = pkgs.apple-cursor;
      name = "macOS";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };
    sessionVariables = lib.mkIf (!isDarwin) {
      NIXOS_OZONE_WL = "1";
    };
    shell.enableZshIntegration = true;
    shellAliases = {
      rebuild = if isDarwin then
        "sudo darwin-rebuild switch --flake ~/Developer/dotfiles#${hostName}"
      else
        "sudo nixos-rebuild switch --flake ~/Developer/dotfiles#${hostName}";
      reload = "source ~/.zshrc";
      c = "clear";
      dl = "cd ~/Downloads";
      dt = "cd ~/Desktop";
      dc = "cd ~/Documents";
      dp = "cd ~/Developer";
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "....." = "cd ../../../..";
      "......" = "cd ../../../../..";
      "-" = "cd -";
      f = "fuck";
      ls = "eza";
      cat = "bat";
      lzd = "lazygit";
    };
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/bin"
    ];
  };
}
