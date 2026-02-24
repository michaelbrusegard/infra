{inputs}: let
  inherit (inputs.nixpkgs.lib) composeManyExtensions;
in
  composeManyExtensions [
    (_: prev: import ../packages {pkgs = prev;})
    inputs.yazi.overlays.default
    inputs.brew-nix.overlays.default
    (
      _: prev: let
        inherit (prev.stdenv.hostPlatform) system;
      in {
        inherit (inputs.hyprland.packages.${system}) hyprland xdg-desktop-portal-hyprland;
        inherit (inputs.nixpkgs-otbr.legacyPackages.${system}) openthread-border-router;

        quickshell = inputs.quickshell.packages.${system}.default;
        dms-shell = inputs.dms.packages.${system}.default;
        dms-greeter = inputs.dms.packages.${system}.default;
        dsearch = inputs.dsearch.packages.${system}.default;
        wezterm = inputs.wezterm.packages.${system}.default;
      }
    )
    (
      _: prev: let
        inherit (prev.stdenv.hostPlatform) system;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        inherit
          (pkgs-unstable)
          dgop
          yabai
          jankyborders
          neovim
          vimPlugins
          opencode
          ruff
          uv
          ty
          oxlint
          vtsls
          postgresql
          lazysql
          ;
        eslint = pkgs-unstable.eslint.overrideAttrs (old: {
          meta = (old.meta or {}) // {mainProgram = "eslint";};
        });
        prettier = pkgs-unstable.prettier.overrideAttrs (old: {
          meta = (old.meta or {}) // {mainProgram = "prettier";};
        });
        oxfmt = pkgs-unstable.oxfmt.overrideAttrs (old: {
          meta = (old.meta or {}) // {mainProgram = "oxfmt";};
        });
        biome = pkgs-unstable.biome.overrideAttrs (old: {
          meta = (old.meta or {}) // {mainProgram = "biome";};
        });
      }
    )
  ]
