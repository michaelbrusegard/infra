{ ... }: {
  home.stateVersion = "25.05";
  catppuccin = {
    enable = true;
    flavor = "mocha";
  };
  modules = {
    programs = {
      browser.enable = true;
    };
    terminal = {
      git.enable = true;
      neovim.enable = true;
      shell.enable = true;
      wezterm.enable = true;
    };
  };
};
