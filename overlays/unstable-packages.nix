inputs: _: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
in
{
  inherit (pkgs-unstable)
    aerospace
    jankyborders
    neovim-unwrapped
    vimPlugins
    uv
    ty
    oxlint
    oxfmt
    prettier
    biome
    vtsls
    postgresql
    lazysql
    fluffychat
    flux
    kubectl
    kubernetes-helm
    etcd
    opencloud-desktop
    signal-desktop
    gh-eco
    gh-poi
    gh-dash
    gh-skyline
    gh-stack
    netbird-ui
    netbird
    ;

  feishin = prev.feishin.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      substituteInPlace $out/bin/feishin \
        --replace-fail 'exec -a "$0" ' 'unset ELECTRON_RUN_AS_NODE
      exec -a "$0" '
    '';
  });
  ruff-unstable = pkgs-unstable.ruff;
  eslint = pkgs-unstable.eslint.overrideAttrs (old: {
    meta = (old.meta or { }) // {
      mainProgram = "eslint";
    };
  });
}
