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
        t3code = inputs.t3code.packages.${system}.t3-code;
      }
    )
    (
      _: prev: let
        inherit (prev.stdenv.hostPlatform) system;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
          # TODO: Remove after nixpkgs merges ast-grep 0.41.1 (NixOS/nixpkgs#498607)
          overlays = [
            (_: uprev: {
              ast-grep = uprev.ast-grep.overrideAttrs {doCheck = false;};
            })
          ];
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
          opencode-desktop
          uv
          ty
          oxlint
          vtsls
          postgresql
          lazysql
          colima
          element-desktop
          flux
          kubectl
          kubernetes-helm
          ;
        ruff-unstable = pkgs-unstable.ruff;
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
