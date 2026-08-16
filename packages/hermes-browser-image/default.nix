{
  dockerTools,
  pkgs,
  runCommand,
}: let
  ublockOriginLiteId = "ddkjiahejlhfcafbddmgiahcphecmpfh";
  chromiumPolicy = pkgs.writeText "hermes-browser-policy.json" (
    builtins.toJSON {
      ExtensionInstallForcelist = [
        "${ublockOriginLiteId};https://clients2.google.com/service/update2/crx"
      ];
      "3rdparty".extensions.${ublockOriginLiteId}.disableFirstRunPage = true;
    }
  );

  fontconfigFile = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [
      dejavu_fonts
      liberation_ttf
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  browserLauncher = pkgs.writeShellApplication {
    name = "chromium";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      novnc
      procps
      x11vnc
      xkbcomp
      xkeyboard_config
      xorg-server
    ];
    text = ''
      export DISPLAY=:99
      export XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb
      mkdir -p /tmp/.X11-unix
      rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

      Xvfb "$DISPLAY" \
        -screen 0 1440x900x24 \
        -xkbdir "$XKB_CONFIG_ROOT" \
        -nolisten tcp \
        -noreset \
        -ac &
      xvfb_pid=$!
      browser_pid=
      novnc_pid=
      x11vnc_pid=

      cleanup() {
        if [ -n "$browser_pid" ]; then
          kill -TERM "$browser_pid" 2>/dev/null || true
        fi
        if [ -n "$novnc_pid" ]; then
          kill -TERM "$novnc_pid" 2>/dev/null || true
        fi
        if [ -n "$x11vnc_pid" ]; then
          kill -TERM "$x11vnc_pid" 2>/dev/null || true
        fi
        kill -TERM "$xvfb_pid" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM

      for _ in $(seq 1 50); do
        if [ -S /tmp/.X11-unix/X99 ]; then
          break
        fi
        if ! kill -0 "$xvfb_pid" 2>/dev/null; then
          echo "Xvfb exited before display $DISPLAY became ready" >&2
          exit 1
        fi
        sleep 0.1
      done
      if [ ! -S /tmp/.X11-unix/X99 ]; then
        echo "Timed out waiting for display $DISPLAY" >&2
        exit 1
      fi

      x11vnc \
        -display "$DISPLAY" \
        -localhost \
        -forever \
        -shared \
        -nopw \
        -rfbport 5900 \
        -quiet &
      x11vnc_pid=$!

      novnc \
        --listen 127.0.0.1:6080 \
        --vnc 127.0.0.1:5900 \
        --file-only &
      novnc_pid=$!

      ${pkgs.chromium}/bin/chromium "$@" &
      browser_pid=$!
      wait "$browser_pid"
    '';
  };

  tools = pkgs.buildEnv {
    name = "hermes-browser-tools";
    paths = with pkgs; [
      bash
      browserLauncher
      cacert
      coreutils
      curl
      gnugrep
      procps
      tzdata
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
    extraCommands = ''
      mkdir -p etc/chromium/policies/managed
      cp ${chromiumPolicy} etc/chromium/policies/managed/hermes-browser.json
      chmod 444 etc/chromium/policies/managed/hermes-browser.json
    '';
    config = {
      Entrypoint = ["${browserLauncher}/bin/chromium"];
      Env = [
        "HOME=/opt/browser"
        "PATH=${tools}/bin"
        "FONTCONFIG_FILE=/etc/fonts.conf"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "TZ=Europe/Oslo"
        "TZDIR=${pkgs.tzdata}/share/zoneinfo"
      ];
      User = "10000:10000";
      WorkingDir = "/opt/browser";
      Labels = {
        "org.opencontainers.image.description" = "Minimal Chromium sidecar for Hermes Agent";
        "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
      };
    };
  }
