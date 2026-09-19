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
    t3code
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
      version = "2.1.278";
      platforms = {
        "darwin-arm64".checksum = "bd245662fb8a0e321b3bf133e930371d6563c387527885f30b2613aef3ba14d6";
        "darwin-x64".checksum = "c522425e3d42275d2ac2238757ef8ba7f80d165a934044ec5a7a5fd7d7b9950b";
        "linux-arm64".checksum = "7de6cab134e48321148e30182c98614118e8f4666819412bead45865190b34ed";
        "linux-x64".checksum = "5c4735937844e84f8a93306e841a5b0e12252909b07870f789b190468da147ab";
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
