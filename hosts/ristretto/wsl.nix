{userName, ...}: {
  wsl = {
    enable = true;
    defaultUser = userName;
    useWindowsDriver = true;
    wslConf.automount.enabled = true;
  };
}
