{ ... }: {
  home.stateVersion = "25.05";
  catppuccin.flavor = "mocha";
  catppuccin.enable = true;
  imports = [
    ../../programs/shell
    ../../programs/git
    ../../programs/neovim
    ../../programs/wezterm
    ../../programs/zen-browser
  ];
};
