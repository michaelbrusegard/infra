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
    neovim-unwrapped
    vimPlugins
    claude-code
    codex
    pi-coding-agent
    uv
    ty
    oxlint
    vtsls
    postgresql
    lazysql
    fluffychat
    flux
    kubectl
    kubernetes-helm
    etcd
    protonmail-desktop
    proton-pass
    nextcloud-client
    nextcloud-talk-desktop
    signal-desktop
    ;

  netbird = pkgs-unstable.netbird.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace client/cmd/kubernetes.go \
          --replace-fail $'\t\tif err != nil {\n\t\t\treturn nil, err\n\t\t}' \
                         $'\t\tif err != nil {\n\t\t\tlog.Debugf("could not resolve reverse DNS for peer %s: %v", peer.IP, err)\n\t\t\tcontinue\n\t\t}'
      '';
  });
  inherit (pkgs-unstable) netbird-ui;
  feishin = prev.feishin.overrideAttrs (old: {
    postFixup =
      (old.postFixup or "")
      + ''
        substituteInPlace $out/bin/feishin \
          --replace-fail 'exec -a "$0" ' 'unset ELECTRON_RUN_AS_NODE
        exec -a "$0" '
      '';
  });
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
