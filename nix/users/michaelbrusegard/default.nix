{ ... }: {
  home.stateVersion = "25.05";
  catppuccin.flavor = "mocha";
  catppuccin.enable = true;
  imports = [
    ../../programs/git
    ../../programs/zsh
    ../../programs/yazi
    ../../programs/neovim
    ../../programs/wezterm
    ../../programs/zen-browser
  ];
};
