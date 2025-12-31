{inputs}: [
  (final: prev: import ../packages {pkgs = final;})
  inputs.nur.overlays.default
  inputs.yazi.overlays.default
  inputs.catppuccin-themes.overlays.default
  inputs.brew-nix.overlays.default
  (final: prev: {
    inherit (inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}) hyprland;
    inherit (inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}) xdg-desktop-portal-hyprland;
  })
  (final: prev: {wezterm = inputs.wezterm.packages.${prev.stdenv.hostPlatform.system}.default;})
  (final: prev: {inherit (inputs.nixpkgs-otbr.legacyPackages.${prev.stdenv.hostPlatform.system}) openthread-border-router;})
  (
    final: prev: let
      inherit (prev.stdenv.hostPlatform) system;
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      inherit (pkgs-unstable) quickshell;
      inherit (pkgs-unstable) yabai;
      inherit (pkgs-unstable) jankyborders;
      inherit (pkgs-unstable) neovim;
      inherit (pkgs-unstable) tree-sitter;
      inherit (pkgs-unstable) lua5_1;
      lua51Packages = {
        inherit (pkgs-unstable.lua51Packages) luarocks;
      };
      inherit (pkgs-unstable) texliveFull;
      inherit (pkgs-unstable) opencode;
    }
  )
]
