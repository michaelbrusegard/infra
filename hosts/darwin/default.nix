{ ... }: {
  imports = [
    ./environment.nix
    ./fonts.nix
    ./homebrew.nix
    ./launchd.nix
    ./security.nix
    ./system.nix
    ./services.nix
  ];
}
