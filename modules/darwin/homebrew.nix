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
      # Brew Bundle 6 deprecated `--cleanup` into a dry run that reports what it
      # would remove and then exits 1, which aborts activation. `--force-cleanup`
      # is the flag that still performs the cleanup, so drive it through
      # extraFlags instead of `cleanup = "zap"`, which emits `--cleanup --zap`.
      # Unlike `--force`, `--force-cleanup` does not also force the installs.
      cleanup = "none";
      extraFlags = [
        "--force-cleanup"
        "--zap"
      ];
      upgrade = true;
    };
    # homebrew/homebrew-core and homebrew/homebrew-cask have to be listed even
    # though nix-homebrew provides them: Brew Bundle 6 dropped homebrew/cask
    # from its cleanup ignore list, so cleanup tries to untap it, fails because
    # proton-drive is installed from it, and aborts activation.
    taps = [
      "homebrew/homebrew-core"
      "homebrew/homebrew-cask"
      "michaelbrusegard/homebrew-extras"
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
    # Brew Bundle refuses to load third-party formulae and casks unless their
    # tap is trusted, and the trust option has no nix-darwin equivalent. The
    # netbird formula is declared explicitly rather than left implicit as the
    # cask's dependency so that it gets upgraded alongside the UI.
    extraConfig = ''
      tap "netbirdio/tap", trusted: { formulae: ["netbird"], casks: ["netbird-ui"] }
      brew "netbirdio/tap/netbird"
      cask "netbirdio/tap/netbird-ui"
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
