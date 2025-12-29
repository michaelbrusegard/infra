{ inputs }:
[
  inputs.nur.overlays.default
  inputs.yazi.overlays.default
  inputs.catppuccin-themes.overlays.default
  (final: prev: {
    hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.hyprland;
    xdg-desktop-portal-hyprland = inputs.hyprland.packages.${prev.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  })
  (final: prev: { wezterm = inputs.wezterm.packages.${prev.stdenv.hostPlatform.system}.default; })
  (final: prev: { openthread-border-router = inputs.nixpkgs-otbr.legacyPackages.${prev.stdenv.hostPlatform.system}.openthread-border-router; })
  (final: prev: { quickshell = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.quickshell; })
  (final: prev: { yabai = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.yabai; })
  (final: prev: { jankyborders = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.jankyborders; })
  (final: prev: { neovim = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.neovim; })
  (final: prev: { tree-sitter = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.tree-sitter; })
  (final: prev: { lua5_1 = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.lua5_1; })
  (final: prev: { lua51Packages.luarocks = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.lua51Packages.luarocks; })
  (final: prev: { texliveFull = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.texliveFull; })
  (final: prev: { opencode = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.opencode; })
  (final: prev: { breaktimer = import ../packages/breaktimer.nix { pkgs = final; }; })
]
