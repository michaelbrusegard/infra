{ ... }: {
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    global.brewfile = true;
    casks = [
      element
      altserver
      legcord
      microsoft-outlook
      obsidian
      proton-mail
      proton-pass
      protonvpn
      proton-drive
      zen-browser
      riscv-tools
    ];
    masApps = {
      "Proton Pass for Safari" = 6502835663;
      "Wipr" = 1662217862;
      "WireGuard" = 1451685025;
      "Messenger" = 1480068668;
      "Affinity Designer 2" = 1616831348;
      "Affinity Photo 2" = 1616822987;
      "Affinity Publisher 2" = 1606941598;
      "Keynote" = 409183694;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "Developer" = 640199958;
      "Xcode" = 497799835;
    };
  };
};
