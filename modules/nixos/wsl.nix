{users, ...}: {
  wsl = {
    enable = true;
    defaultUser = builtins.head users;
    useWindowsDriver = true;
    wslConf.automount.enabled = true;
  };
}
