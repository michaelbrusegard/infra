{ isDarwin, ... }: {
  modules = {
    browser.enable = true;
    cli.enable = true;
    dev.enable = true;
    ghostty.enable = true;
    git.enable = true;
    gui.enable = true;
    mpv.enable = true;
    neovim.enable = true;
    pentest.enable = true;
    shell.enable = true;
    silicon.enable = true;
    ssh.enable = true;
    wayland.enable = !isDarwin;
    wezterm.enable = true;
    wine.enable = !isDarwin;
    xdg.enable = true;
    yazi.enable = true;
  };
}
