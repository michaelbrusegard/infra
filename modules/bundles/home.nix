{ inputs, ... }: {
  # What a user gets on top of their own profile, by the kind of machine. The
  # system bundles and the Mac pick one, so a feature that only makes sense on
  # a desktop is never imported on a server or under WSL.
  flake.modules.homeManager = {
    graphical.imports = with inputs.self.modules.homeManager; [
      android
      ardia
      craft
      desktop-apps
      kitty
      mpv
      slicer
    ];

    desktop.imports = with inputs.self.modules.homeManager; [
      graphical
      dms
      dux-files
      gaming
      gnome-keyring
      groupware
      hex
      hyprland
    ];

    mac.imports = with inputs.self.modules.homeManager; [
      graphical
      launchd
    ];
  };
}
