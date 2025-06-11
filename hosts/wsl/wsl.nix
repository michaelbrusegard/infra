{ userName, ... }: {
  wsl = {
    enable = true;
    defaultUser = userName;
    useWindowsDriver = true;
    startMenuLaunchers = true;
    wslConf.automount.enabled = true;
  };
}
