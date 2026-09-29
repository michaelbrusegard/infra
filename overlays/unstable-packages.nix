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
    chatgpt
    rustdesk-flutter
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
    gh-eco
    gh-dash
    gh-skyline
    ;

  gh-poi = pkgs-unstable.gh-poi.overrideAttrs {
    version = "0.18.4";
    src = prev.fetchFromGitHub {
      owner = "seachicken";
      repo = "gh-poi";
      rev = "v0.18.4";
      hash = "sha256-L4FL9FJMojBdHmsWCIPTtWLoIDeZSU1Kt52URmS8PTw=";
    };
  };

  gh-stack = pkgs-unstable.gh-stack.overrideAttrs {
    version = "0.1.1";
    src = prev.fetchFromGitHub {
      owner = "github";
      repo = "gh-stack";
      tag = "v0.1.1";
      hash = "sha256-jwfqiCnCOOW0AKA52hbgvCCoLzfFX+QfM+vXABkzZgw=";
    };
  };

  # Keep Claude Code current while nixpkgs-unstable lags the published release.
  claude-code = pkgs-unstable.claude-code.override {
    manifest = {
      version = "2.1.285";
      platforms = {
        "darwin-arm64".checksum = "51f09bd1e021d9fa8a1864c179799bd37cb39962a937935c5cf6823398e86db4";
        "darwin-x64".checksum = "24835f7ca4b4338c33ad21c98a3402d9c22f89b8055075d18828e97973844ec3";
        "linux-arm64".checksum = "24fac77749bed3d91365d6b6915aa4b824e14318ecb6bc17adbc192f01c9173d";
        "linux-x64".checksum = "33dad1ec615a2e08cc78b494f05c110e49916de2c79d78ec8799ebf46b233d29";
      };
    };
  };

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
