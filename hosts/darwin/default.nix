{ ... }: {
  imports = [
    ./environment.nix
    ./fonts.nix
    ./homebrew.nix
    ./launchd.nix
    ./system.nix
    ./services.nix
  ];
}
