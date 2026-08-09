{
  dockerTools,
  pkgs,
  runCommand,
}: let
  fontconfigFile = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
    ];
  };

  tools = pkgs.buildEnv {
    name = "hermes-browser-tools";
    paths = with pkgs; [
      cacert
      chromium
      curl
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
      "/share"
    ];
  };

  root = runCommand "hermes-browser-root" {} ''
    mkdir -p "$out/etc" "$out/opt/browser" "$out/tmp"
    ln -s ${fontconfigFile} "$out/etc/fonts.conf"
    cat > "$out/etc/passwd" <<'EOF'
    root:x:0:0:root:/root:/noshell
    browser:x:10000:10000:Hermes Browser:/opt/browser:/noshell
    EOF
    cat > "$out/etc/group" <<'EOF'
    root:x:0:
    browser:x:10000:
    EOF
    chmod 1777 "$out/tmp"
  '';
in
  dockerTools.buildLayeredImage {
    name = "ghcr.io/michaelbrusegard/hermes-browser";
    tag = "nix";
    contents = [
      tools
      root
    ];
    config = {
      Entrypoint = ["${pkgs.chromium}/bin/chromium"];
      Env = [
        "HOME=/opt/browser"
        "PATH=${tools}/bin"
        "FONTCONFIG_FILE=/etc/fonts.conf"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      ];
      User = "10000:10000";
      WorkingDir = "/opt/browser";
      Labels = {
        "org.opencontainers.image.description" = "Minimal Chromium sidecar for Hermes Agent";
        "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
      };
    };
  }
