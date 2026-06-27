inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
  # TODO: Remove these NetBird version overrides once nixpkgs has 0.72.4 or newer.
  netbirdVersion = "0.72.4";
  netbirdSrc = prev.fetchFromGitHub {
    owner = "netbirdio";
    repo = "netbird";
    rev = "v${netbirdVersion}";
    hash = "sha256-YRXXuaqnQBLODcz/FNpIG9Ht+6VGRknE2Q6Q5ZaAIus=";
  };
  netbirdVendorHash = "sha256-6FN7l+e75Pw2+v0sktomlck+7daro1i6c4ZV53SRePI=";
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
    claude-code
    codex
    uv
    ty
    oxlint
    vtsls
    postgresql
    lazysql
    colima
    fluffychat
    flux
    kubectl
    kubernetes-helm
    etcd
    protonmail-desktop
    proton-pass
    nextcloud-talk-desktop
    signal-desktop
    ;

  netbird = pkgs-unstable.netbird.overrideAttrs (_: {
    version = netbirdVersion;
    src = netbirdSrc;
    vendorHash = netbirdVendorHash;
    postPatch = ''
      substituteInPlace client/cmd/kubernetes.go \
        --replace-fail $'\t\tif err != nil {\n\t\t\treturn nil, err\n\t\t}' \
                       $'\t\tif err != nil {\n\t\t\tlog.Debugf("could not resolve reverse DNS for peer %s: %v", peer.IP, err)\n\t\t\tcontinue\n\t\t}'
    '';
  });
  netbird-ui = pkgs-unstable.netbird-ui.overrideAttrs (_: {
    version = netbirdVersion;
    src = netbirdSrc;
    vendorHash = netbirdVendorHash;
  });
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
