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
    brews = [
      "mas"
    ];
    casks = [
      # TODO: re-enable once the upstream homebrew-cask scribus definition
      # stops declaring conflicting `depends_on macos` (on_arm/on_intel
      # versions plus a bare `depends_on :macos`), which brew rejects with
      # "Only a single 'depends_on macos' is allowed". The nixpkgs scribus
      # is also marked broken on darwin, so there's no Nix fallback.
      # "scribus"
      "proton-drive"
    ];
    extraConfig = ''
      cask "netbirdio/tap/netbird-ui", trusted: true
    '';
    masApps = {
      "Amphetamine" = 937984704;
      "Proton Pass for Safari" = 6502835663;
      "Wipr" = 1662217862;
      "Developer" = 640199958;
      "TestFlight" = 899247664;
      "Xcode" = 497799835;
      "DaVinci Resolve" = 571213070;
    };
  };
}
