{ ... }: {
  home.stateVersion = "25.05";
  modules = {
    terminal = {
      git.enable = true;
      neovim.enable = true;
      shell.enable = true;
      wezterm.enable = true;
    };
  };
};
