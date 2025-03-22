{ config, isDarwin, ... }:
{
  home = {
    stateVersion = "25.05";
    language = {
      base = "en_GB.UTF-8";
      ctype = "en_GB.UTF-8";
      messages = "en_GB.UTF-8";
      address = "nb_NO.UTF-8";
      collate = "nb_NO.UTF-8";
      measurement = "nb_NO.UTF-8";
      monetary = "nb_NO.UTF-8";
      name = "nb_NO.UTF-8";
      numeric = "nb_NO.UTF-8";
      paper = "a4";
      telephone = "nb_NO.UTF-8";
      time = "nb_NO.UTF-8";
    };
    shellAliases = {
      rebuild = if isDarwin then
        "darwin-rebuild switch --flake ~/Developer/dotfiles#${config.networking.hostName}"
      else
        "sudo nixos-rebuild switch --flake ~/Developer/dotfiles#${config.networking.hostName}";
      reload = "source ~/.zshrc";
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
