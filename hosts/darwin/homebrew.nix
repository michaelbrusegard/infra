{ config, userName, homebrew-core, homebrew-cask, homebrew-extras, ... }: {
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = userName;
    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
      "michaelbrusegard/homebrew-extras" = homebrew-extras;
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
    taps = builtins.attrNames config.nix-homebrew.taps;
    brews = [
      "nsis"
    ];
    casks = [
      "jordanbaird-ice"
      "yabai-indicator"
      "linearmouse"
      "aldente"
      "breaktimer"
      "stolendata-mpv"
      "altserver"
      "ghostty"
      "vivaldi"
      "burp-suite"
      "element"
      "slack"
      "legcord"
      "obsidian"
      "proton-pass"
      "proton-mail"
      "protonvpn"
      "proton-drive"
      "libreoffice"
      "transmission"
      "inkscape"
      "gimp"
      "scribus"
      "affinity"
      "blender"
      "freecad"
      "orcaslicer"
      "bambu-studio"
      "betaflight-configurator"
      "qgis"
      "notion"
      "audacity"
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
      "DaVinci Resolve" = 571213070;
    };
  };
}
