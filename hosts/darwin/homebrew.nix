{ userName, homebrew-core, homebrew-cask, homebrew-riscv, ... }: {
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = userName;
    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
      "homebrew/homebrew-riscv" = homebrew-riscv;
    };
    mutableTaps = false;
  };
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    global.brewfile = true;
    casks = [
      "element"
      "altserver"
      "legcord"
      "microsoft-outlook"
      "obsidian"
      "proton-mail"
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
