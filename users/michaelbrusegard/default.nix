{ isDarwin, isWsl, ... }: {
  modules = {
    browser.enable = !isWsl;
    cli.core.enable = true;
    cli.desktop.enable = true;
    dev.enable = true;
    ghostty.enable = !isWsl;
    git.enable = true;
    gui.enable = !(isDarwin || isWsl);
    mpv.enable = !isWsl;
    neovim.enable = true;
    opencode.enable = true;
    pentest.enable = true;
    shell.enable = true;
    silicon.enable = true;
    ssh.enable = true;
    wayland.enable = !(isDarwin || isWsl);
    wezterm.enable = true;
    xdg.enable = !isDarwin;
    yazi.enable = true;
    zathura.enable = !isWsl;
  };
}
