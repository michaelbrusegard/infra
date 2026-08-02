{
  dockerTools,
  hermes-agent,
  pkgs,
  runCommand,
}: let
  pythonTools = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.ipykernel
    pythonPackages.jupyter
  ]);

  tools = pkgs.buildEnv {
    name = "hermes-agent-tools";
    paths = with pkgs; [
      bashInteractive
      bind
      cacert
      coreutils
      curl
      file
      fluxcd
      gh
      git
      himalaya
      jq
      kubectl
      kubernetes-helm
      netcat
      opencode
      openssh
      opentofu
      ripgrep
      socat
      stern
      unzip
      yq-go
      pythonTools
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
      "/share"
    ];
  };

  root = runCommand "hermes-agent-root" {} ''
    mkdir -p "$out/etc" "$out/opt/data" "$out/tmp"
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
      tools
      root
    ];
    config = {
      Entrypoint = ["${hermes-agent}/bin/hermes"];
      Env = [
        "HOME=/opt/data"
        "HERMES_HOME=/opt/data"
        "PATH=${tools}/bin:${hermes-agent}/bin"
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
