inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
  # NetBird 0.77.1's loopback XDP multi-buffer support can panic Linux 6.3+.
  # Keep the client and UI aligned on the last release before the regression.
  netbirdVersion = "0.77.0";
  netbirdSrc = prev.fetchFromGitHub {
    owner = "netbirdio";
    repo = "netbird";
    rev = "v${netbirdVersion}";
    hash = "sha256-w72ylRblfC20X4h1E7vuycWziLfWE+cCHuIaf7czFb8=";
  };
  netbirdVendorHash = "sha256-kbVBjQUZUp9VZ67Ug4VWtmp2qZw5hLtxLg8utyNCNGg=";
in {
  inherit
    (pkgs-unstable)
    aerospace
    dgop
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
    protonmail-desktop
    proton-pass
    nextcloud-client
    nextcloud-talk-desktop
    signal-desktop
    gh-eco
    gh-poi
    gh-dash
    gh-skyline
    gh-stack
    ;

  netbird = pkgs-unstable.netbird.overrideAttrs (old: {
    version = netbirdVersion;
    src = netbirdSrc;
    vendorHash = netbirdVendorHash;
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace client/cmd/kubernetes.go \
          --replace-fail $'\t\tif err != nil {\n\t\t\treturn nil, err\n\t\t}' \
                         $'\t\tif err != nil {\n\t\t\tlog.Debugf("could not resolve reverse DNS for peer %s: %v", peer.IP, err)\n\t\t\tcontinue\n\t\t}'
      '';
  });
  netbird-ui = pkgs-unstable.netbird-ui.overrideAttrs {
    version = netbirdVersion;
    src = netbirdSrc;
    vendorHash = netbirdVendorHash;
  };
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
}
