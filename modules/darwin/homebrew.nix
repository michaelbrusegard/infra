{
  inputs,
  config,
  ...
}: {
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = config.system.primaryUser;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "michaelbrusegard/homebrew-extras" = inputs.homebrew-extras;
      "netbirdio/homebrew-tap" = inputs.homebrew-netbird;
    };
    mutableTaps = false;
    autoMigrate = true;
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
    taps = [
      "michaelbrusegard/homebrew-extras"
      "netbirdio/homebrew-tap"
    ];
    casks = [
      "netbird-ui"
      "scribus"
      "proton-drive"
    ];
    masApps = {
      "Proton Pass for Safari" = 6502835663;
      "Wipr" = 1662217862;
      "Developer" = 640199958;
      "Xcode" = 497799835;
      "DaVinci Resolve" = 571213070;
    };
  };
}
