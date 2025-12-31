{ inputs }:
[
  inputs.nur.overlays.default
  inputs.yazi.overlays.default
  inputs.catppuccin-themes.overlays.default
  inputs.brew-nix.overlays.default
  (final: prev: {
    hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.hyprland;
    xdg-desktop-portal-hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  })
  (final: prev: { wezterm = inputs.wezterm.packages.${prev.stdenv.hostPlatform.system}.default; })
  (final: prev: { openthread-border-router = inputs.nixpkgs-otbr.legacyPackages.${prev.stdenv.hostPlatform.system}.openthread-border-router; })
  (final: prev:
    let
      system = prev.stdenv.hostPlatform.system;
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      quickshell = pkgs-unstable.quickshell;
      yabai = pkgs-unstable.yabai;
      jankyborders = pkgs-unstable.jankyborders;
      neovim = pkgs-unstable.neovim;
      tree-sitter = pkgs-unstable.tree-sitter;
      lua5_1 = pkgs-unstable.lua5_1;
      lua51Packages = {
        inherit (pkgs-unstable.lua51Packages) luarocks;
      };
      texliveFull = pkgs-unstable.texliveFull;
      opencode = pkgs-unstable.opencode;
    }
  )
  (final: prev: { breaktimer = import ../packages/breaktimer.nix { pkgs = final; }; })
]
