{ ... }:

{
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    global.brewfile = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    taps = [
      "michaelbrusegard/homebrew-extras"
    ];
    casks = [
      "yabai-indicator"
      "vivaldi"
      "scribus"
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
