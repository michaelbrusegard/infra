{
  fonts = import ./fonts.nix;
  home-manager = import ./home-manager.nix;
  homebrew = import ./homebrew.nix;
  kanata = import ./kanata.nix;
  launchd = import ./launchd.nix;
  mime = import ./mime.nix;
  networking = import ./networking.nix;
  nix = import ./nix.nix;
  openssh = import ./openssh.nix;
  secrets = import ./secrets.nix;
  security = import ./security.nix;
  system = import ./system.nix;
  virtualisation = import ./virtualisation.nix;
  wallpaper = import ./wallpaper.nix;
  yabai = import ./yabai.nix;
}
