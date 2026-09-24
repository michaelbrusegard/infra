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
    # opencode is pinned locally in packages/, but its build wants the newer
    # models-dev that exposes a jsonschema output.
    models-dev
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

  # Keep Claude Code current while nixpkgs-unstable is still on 2.1.245.
  claude-code = pkgs-unstable.claude-code.override {
    manifest = {
      version = "2.1.281";
      platforms = {
        "darwin-arm64".checksum = "a922981f6f3b55a251ef9f9dbaa0621a5f99cbcb5ca67f8a797476ccfc83f626";
        "darwin-x64".checksum = "a9355cbb0d291ce948efcf61a6ef397401672f64fa5e5e67bca092fed6cd9088";
        "linux-arm64".checksum = "dd27b36438a4fed1670cd29bad2fda6a73b628b6da55443e5c2f647fe6ed328f";
        "linux-x64".checksum = "56fe3da88458465fb27d7e9299dddb3fead55750fb9c2de795f233b5eea6dce1";
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
