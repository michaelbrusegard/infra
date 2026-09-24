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
    pi-coding-agent
    opencode
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
      version = "2.1.280";
      platforms = {
        "darwin-arm64".checksum = "387a5c5dcdbb815085edf0baf79591f9d8894efe922bceaf3d75b1b08055229d";
        "darwin-x64".checksum = "c1d32d87630482250633208ab77855429b24010ae3086a7ff7539b57b93168d4";
        "linux-arm64".checksum = "92f2b4fd05d0bdcf7b9a0d4e0ecef4a1e4b368b290cd8fd07cff9a50013f45a2";
        "linux-x64".checksum = "1e08503dbdf3c2cb0d706d32f3408277388d1c76ef108673e8fe42c1b322925b";
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
