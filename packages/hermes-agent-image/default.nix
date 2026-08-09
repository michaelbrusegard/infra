{
  dockerTools,
  hermes-agent,
  pkgs,
  runCommand,
}: let
  markitdownPptx = pkgs.python3Packages.markitdown.overrideAttrs {
    dependencies = with pkgs.python3Packages; [
      beautifulsoup4
      defusedxml
      lxml
      markdownify
      pathvalidate
      puremagic
      python-pptx
      requests
    ];
    doCheck = false;
    nativeCheckInputs = [];
  };

  pythonTools = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.defusedxml
    pythonPackages.ipykernel
    pythonPackages.jupyter
    markitdownPptx
    pythonPackages.nbformat
    pythonPackages.pillow
    pythonPackages.pymupdf
    pythonPackages.pymupdf4llm
    pythonPackages.python-docx
    pythonPackages.python-pptx
    pythonPackages.requests
    pythonPackages.websocket-client
    pythonPackages.youtube-transcript-api
  ]);

  blogwatcherRelease =
    {
      x86_64-linux = {
        arch = "amd64";
        hash = "sha256-DYBO+f+6Z6H6taBtzo+SC2f6i93+hOQIZ8nRICr0Qzk=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-0vc0FXu8KS53Zoz7s60lvE46YkaySUnetdWqiut7Z4A=";
      };
    }
    .${
      pkgs.stdenv.hostPlatform.system
    }
    or (throw "blogwatcher-cli is unsupported on ${pkgs.stdenv.hostPlatform.system}");

  blogwatcherCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "blogwatcher-cli";
    version = "0.2.1";
    src = pkgs.fetchurl {
      url = "https://github.com/JulienTant/blogwatcher-cli/releases/download/v0.2.1/blogwatcher-cli_linux_${blogwatcherRelease.arch}.tar.gz";
      inherit (blogwatcherRelease) hash;
    };
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      install -Dm755 blogwatcher-cli "$out/bin/blogwatcher-cli"
      runHook postInstall
    '';
  };

  jupyterLiveKernelScript = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/hamelsmu/hamelnb/192f491fd388bbc190bcaa95542c5d5f98dae2ab/skills/jupyter-live-kernel/scripts/jupyter_live_kernel.py";
    hash = "sha256-wE4PMp5QglawRmlKjR6i0tLldTuCIYy/Z9etAAG9n0Q=";
  };

  jupyterLiveKernel = pkgs.writeShellApplication {
    name = "jupyter-live-kernel";
    runtimeInputs = [pythonTools];
    text = ''
      exec python3 ${jupyterLiveKernelScript} "$@"
    '';
  };

  nodeTools = pkgs.buildNpmPackage {
    pname = "hermes-agent-node-tools";
    version = "1.0.0";
    src = ./node-tools;
    npmDepsHash = "sha256-vlLaSLfWlYqX3nb7X7eIhWbfz5bx/V3ujV8HEHxf8TY=";
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/node_modules"
      cp -R node_modules/. "$out/lib/node_modules/"
      runHook postInstall
    '';
  };

  tools = pkgs.buildEnv {
    name = "hermes-agent-tools";
    paths = with pkgs; [
      agent-browser
      bashInteractive
      bind
      blogwatcherCli
      cacert
      coreutils
      curl
      file
      fluxcd
      gh
      git
      gnused
      himalaya
      jupyterLiveKernel
      jq
      kubectl
      kubernetes-helm
      libreoffice-fresh
      netcat
      nodejs-slim
      ocrmypdf
      openssh
      opentofu
      poppler-utils
      ripgrep
      socat
      stern
      tesseract
      unzip
      yq-go
      zip
      pythonTools
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
      "/share"
    ];
  };

  root = runCommand "hermes-agent-root" {} ''
    mkdir -p "$out/etc" "$out/opt/data/workspace" "$out/tmp"
    cat > "$out/etc/passwd" <<'EOF'
    root:x:0:0:root:/root:/bin/bash
    hermes:x:10000:10000:Hermes Agent:/opt/data:/bin/bash
    EOF
    cat > "$out/etc/group" <<'EOF'
    root:x:0:
    hermes:x:10000:
    EOF
    chmod 1777 "$out/tmp"
  '';
in
  dockerTools.buildLayeredImage {
    name = "ghcr.io/michaelbrusegard/hermes-agent";
    tag = "nix";
    contents = [
      hermes-agent
      nodeTools
      tools
      root
    ];
    config = {
      Entrypoint = ["${hermes-agent}/bin/hermes"];
      Env = [
        "HOME=/opt/data"
        "HERMES_HOME=/opt/data"
        "PATH=${tools}/bin:${hermes-agent}/bin"
        "NODE_PATH=${nodeTools}/lib/node_modules"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "PYTHONDONTWRITEBYTECODE=1"
        "PIP_DISABLE_PIP_VERSION_CHECK=1"
      ];
      User = "10000:10000";
      WorkingDir = "/opt/data/workspace";
      Labels = {
        "org.opencontainers.image.description" = "Hermes Agent with a fully declarative Nix toolchain";
        "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
      };
    };
  }
