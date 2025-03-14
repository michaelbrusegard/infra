{ ... }: {
  home.stateVersion = "25.05";
  catppuccin.flavor = "mocha";
  catppuccin.enable = true;
  imports = [
    ../../programs/zsh
    ../../programs/git
    ../../programs/neovim
    ../../programs/wezterm
    ../../programs/zen-browser
  ];
};
