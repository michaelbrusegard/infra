{ ... }: {
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    global.brewfile = true;
    casks = [
      "element-desktop"
      "altserver"
      "legcord"
      "microsoft-outlook"
      "obsidian"
      "proton-mail-bridge"
      "protonvpn"
      "proton-drive"
      "riscv-tools"
      "safe-exam-browser"
    ];
    masApps = {
      "Proton Pass for Safari" = 6502835663;
      "Wipr" = 1662217862;
      "WireGuard" = 1451685025;
      "Messenger" = 1480068668;
      "Developer" = 640199958;
      "Xcode" = 497799835;
      "DaVinci Resolve" = 571213070;
    };
  };
}
