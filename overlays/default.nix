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

        quickshell = inputs.quickshell.packages.${system}.default;
        dms-shell = inputs.dms.packages.${system}.default;
        dms-greeter = inputs.dms.packages.${system}.default;
        dsearch = inputs.dsearch.packages.${system}.default;
        wezterm = inputs.wezterm.packages.${system}.default;
        t3code = inputs.t3code.packages.${system}.t3-code;
      }
    )
    # nixpkgs 26.05's firefox wrapper emits an unquoted
    # `touch $out/Applications/<App Name>.app/.../is-packaged-app`, which
    # breaks under bash when the app name contains shell metacharacters
    # (e.g. zen's "Zen Browser (Beta)") on darwin. Quote the path until the
    # stable channel picks up the upstream fix.
    (
      _: prev:
        prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
          wrapFirefox = browser: args: let
            wrapped = prev.wrapFirefox browser args;
          in
            wrapped.overrideAttrs (old: {
              buildCommand =
                builtins.replaceStrings
                ["\ntouch $out/" "/is-packaged-app\n"]
                ["\ntouch \"$out/" "/is-packaged-app\"\n"]
                old.buildCommand;
            });
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
          aerospace
          dgop
          jankyborders
          neovim
          vimPlugins
          opencode
          opencode-desktop
          codex
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
          etcd
          # Pull the nextcloud clients from unstable: the stable 26.05
          # nextcloud server package set (touched transitively) carries a
          # nested-list nativeBuildInputs deprecation warning.
          nextcloud-client
          nextcloud-talk-desktop
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
