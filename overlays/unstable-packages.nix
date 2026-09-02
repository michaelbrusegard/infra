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

  # claude-fable-5-1 requires Claude Code 2.1.251 or newer, while
  # nixpkgs-unstable is still on 2.1.245.
  claude-code = pkgs-unstable.claude-code.override {
    manifest = {
      version = "2.1.258";
      platforms = {
        "darwin-arm64".checksum = "b63136194160791c27cfa7b0403060d85eb0752991625fde8c09f9acacb17c78";
        "darwin-x64".checksum = "c857db5cd712865623bd61e806cf3f7e8e279c9e5c7c0af5eca06ca6717fc7fb";
        "linux-arm64".checksum = "43dc490af55262edcb3e9b1cb315de22cc09ccb08bd52a4c39bc5eabaa63100f";
        "linux-x64".checksum = "704f1334ac65d3e89e1c6c1d7663293ad786a6166afdb71b5075337df630f976";
      };
    };
  };

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
