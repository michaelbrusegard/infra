{ isDarwin, ... }: {
  modules = {
    browser.enable = false;
    cli.enable = true;
    dev.enable = true;
    ghostty.enable = true;
    git.enable = true;
    gui.enable = true;
    wayland.enable = !isDarwin;
    mpv.enable = true;
    neovim.enable = true;
    pentest.enable = true;
    shell.enable = true;
    silicon.enable = true;
    ssh.enable = true;
    wezterm.enable = true;
    xdg.enable = true;
    yazi.enable = true;
  };
}
