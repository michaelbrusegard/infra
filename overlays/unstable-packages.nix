inputs: _: prev: let
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
