{ userName, homebrew-core, homebrew-cask, ... }: {
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = userName;
    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
    };
    mutableTaps = false;
  };
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    global.brewfile = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    brews = [
      "nsis"
    ];
    casks = [
      "raycast"
      "linearmouse"
      "element"
      "altserver"
      "legcord"
      "obsidian"
      "proton-pass"
      "proton-mail"
      "protonvpn"
      "proton-drive"
      "ghostty"
      "chromium"
      "inkscape"
      "gimp"
      "orcaslicer"
      "freecad"
      "betaflight-configurator"
      "blender"
      "qgis"
    ];
    masApps = {
      "Amphetamine" = 937984704;
      "BrightIntosh" = 6452471855;
      "Proton Pass for Safari" = 6502835663;
      "Wipr" = 1662217862;
      "WireGuard" = 1451685025;
      "Keynote" = 409183694;
      "Pages" = 409201541;
      "Numbers" = 409203825;
      "Developer" = 640199958;
      "Xcode" = 497799835;
      "Messenger" = 1480068668;
      "DaVinci Resolve" = 571213070;
    };
  };
}
