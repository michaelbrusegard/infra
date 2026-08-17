{
  dockerTools,
  pkgs,
  runCommand,
}: let
  ublockOriginLiteId = "ddkjiahejlhfcafbddmgiahcphecmpfh";
  ublockOriginLiteVersion = "2026.812.1211";
  ublockOriginLiteCrx = pkgs.fetchurl {
    url = "https://clients2.googleusercontent.com/crx/blobs/Abe5cL5iPjDW5ZJUYXR41Hf3hetLBjRflHjsNb88fI1gS7hxh7pS_HTlL0HvmEAhs2JGtXQ_QYdg8IC9R9cNR3IZMJwoXwCcuICdXiacfzA3ii2QE9gSd1IrYdW9KlXFe9MBAMZSmuXvDSfumN6MpiP8B0tWIgCIm-_NsA/DDKJIAHEJLHFCAFBDDMGIAHCPHECMPFH_2026_812_1211_0.crx";
    hash = "sha256-QjPIOwUbfw6Is8GiL+FjiPECqg0ThT/csEViJH4E1W0=";
  };
  ublockOriginLiteExternal = pkgs.writeText "${ublockOriginLiteId}.json" (
    builtins.toJSON {
      external_crx = "/opt/hermes/extensions/ublock-origin-lite.crx";
      external_version = ublockOriginLiteVersion;
    }
  );
  chromiumPolicy = pkgs.writeText "hermes-browser-policy.json" (
    builtins.toJSON {
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
      findutils
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
      export HERMES_BROWSER_POLICY_TEMPLATE=/opt/hermes/hermes-browser.json
      mkdir -p /tmp/.X11-unix
      rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

      browser_files_root=''${BROWSER_FILES_ROOT:-/opt/browser-files}
      supervisor_dir="$browser_files_root/browser-supervisor"
      status_file="$supervisor_dir/status.json"
      mkdir -p "$supervisor_dir"

      json_escape() {
        local value=$1
        value=''${value//\\/\\\\}
        value=''${value//\"/\\\"}
        value=''${value//$'\n'/\\n}
        value=''${value//$'\r'/\\r}
        value=''${value//$'\t'/\\t}
        printf '%s' "$value"
      }

      iso_now() {
        date -u +%Y-%m-%dT%H:%M:%SZ
      }

      write_status() {
        local state=$1
        local tmp="$status_file.tmp"
        cat >"$tmp" <<EOF
      {
        "updated_at": "$(iso_now)",
        "state": "$(json_escape "$state")",
        "display": "$(json_escape "$DISPLAY")",
        "xvfb_pid": ''${xvfb_pid:-null},
        "x11vnc_pid": ''${x11vnc_pid:-null},
        "novnc_pid": ''${novnc_pid:-null},
        "browser_pid": ''${browser_pid:-null},
        "restart_count": ''${restart_count:-0},
        "last_exit_code": ''${last_exit_code:-null},
        "extension_count": ''${extension_count:-0},
        "managed_policy_count": ''${managed_policy_count:-0}
      }
      EOF
        mv "$tmp" "$status_file"
      }

      if [ ! -d "$HOME" ] || [ ! -w "$HOME" ]; then
        echo "Chromium profile root is not writable: $HOME" >&2
        write_status "profile-not-writable"
        exit 1
      fi

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
      restart_count=0
      last_exit_code=null
      extension_count=0
      managed_policy_count=0
      shutting_down=0

      cleanup() {
        shutting_down=1
        write_status "stopping"
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
        write_status "stopped"
      }
      trap cleanup EXIT INT TERM
      write_status "starting"

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

      managed_policy_dir=/etc/chromium/policies/managed
      mkdir -p "$managed_policy_dir"
      cp "$HERMES_BROWSER_POLICY_TEMPLATE" \
        "$managed_policy_dir/hermes-browser.json"
      if [ -d /opt/browser/policies/managed ]; then
        find /opt/browser/policies/managed -maxdepth 1 -type f -name '*.json' \
          -exec cp {} "$managed_policy_dir/" \;
      fi
      managed_policy_count=$(find "$managed_policy_dir" -maxdepth 1 -type f -name '*.json' | wc -l)

      extra_args=()
      extension_dirs=()
      if [ -d /opt/browser/extensions-unpacked ]; then
        while IFS= read -r manifest; do
          extension_dirs+=("$(dirname "$manifest")")
        done < <(
          find /opt/browser/extensions-unpacked -mindepth 2 -maxdepth 2 \
            -type f -name manifest.json | sort
        )
      fi
      extension_count=''${#extension_dirs[@]}
      if [ "''${#extension_dirs[@]}" -gt 0 ]; then
        IFS=,
        extra_args+=("--load-extension=''${extension_dirs[*]}")
        unset IFS
      fi
      if [ -f /opt/browser/chromium-extra-args ]; then
        while IFS= read -r arg; do
          [ -n "$arg" ] || continue
          extra_args+=("$arg")
        done < /opt/browser/chromium-extra-args
      fi

      while true; do
        write_status "running"
        ${pkgs.chromium}/bin/chromium "$@" "''${extra_args[@]}" &
        browser_pid=$!
        write_status "running"
        set +e
        wait "$browser_pid"
        exit_code=$?
        set -e
        last_exit_code=$exit_code
        browser_pid=
        if [ "$shutting_down" -eq 1 ] || [ "$exit_code" -eq 0 ]; then
          break
        fi
        restart_count=$((restart_count + 1))
        write_status "restarting"
        sleep 2
      done
      write_status "exited"
    '';
  };

  androidViewer = pkgs.writeShellApplication {
    name = "android-viewer";
    runtimeInputs = with pkgs; [
      android-tools
      coreutils
      curl
      gnugrep
      novnc
      procps
      scrcpy
      x11vnc
      xkbcomp
      xkeyboard_config
      xorg-server
    ];
    text = ''
      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        echo "Usage: android-viewer [scrcpy options...]"
        echo "Mirrors ANDROID_SERIAL through scrcpy and serves it over noVNC."
        exit 0
      fi

      export DISPLAY="''${ANDROID_VIEW_DISPLAY:-:100}"
      export XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb
      export HOME="''${HOME:-/tmp/android-viewer-home}"
      serial="''${ANDROID_SERIAL:-127.0.0.1:5555}"
      novnc_listen="''${ANDROID_VIEW_LISTEN:-0.0.0.0:6081}"
      vnc_port="''${ANDROID_VIEW_VNC_PORT:-5901}"
      browser_files_root="''${BROWSER_FILES_ROOT:-/opt/browser-files}"
      supervisor_dir="$browser_files_root/android-viewer"
      status_file="$supervisor_dir/status.json"
      restart_count=0
      last_exit_code=null
      scrcpy_pid=
      x11vnc_pid=
      novnc_pid=
      shutting_down=0

      mkdir -p "$HOME" "$supervisor_dir" /tmp/.X11-unix
      display_number="''${DISPLAY#:}"
      rm -f "/tmp/.X$display_number-lock" "/tmp/.X11-unix/X$display_number"

      json_escape() {
        local value=$1
        value=''${value//\\/\\\\}
        value=''${value//\"/\\\"}
        value=''${value//$'\n'/\\n}
        printf '%s' "$value"
      }

      iso_now() {
        date -u +%Y-%m-%dT%H:%M:%SZ
      }

      write_status() {
        local state=$1
        local tmp="$status_file.tmp"
        cat >"$tmp" <<EOF
      {
        "updated_at": "$(iso_now)",
        "state": "$(json_escape "$state")",
        "serial": "$(json_escape "$serial")",
        "display": "$(json_escape "$DISPLAY")",
        "novnc_listen": "$(json_escape "$novnc_listen")",
        "xvfb_pid": ''${xvfb_pid:-null},
        "x11vnc_pid": ''${x11vnc_pid:-null},
        "novnc_pid": ''${novnc_pid:-null},
        "scrcpy_pid": ''${scrcpy_pid:-null},
        "restart_count": $restart_count,
        "last_exit_code": $last_exit_code
      }
      EOF
        mv "$tmp" "$status_file"
      }

      Xvfb "$DISPLAY" \
        -screen 0 1080x1920x24 \
        -xkbdir "$XKB_CONFIG_ROOT" \
        -nolisten tcp \
        -noreset \
        -ac &
      xvfb_pid=$!

      cleanup() {
        shutting_down=1
        write_status "stopping"
        for pid in "$scrcpy_pid" "$novnc_pid" "$x11vnc_pid" "$xvfb_pid"; do
          if [ -n "$pid" ]; then
            kill -TERM "$pid" 2>/dev/null || true
          fi
        done
        write_status "stopped"
      }
      trap cleanup EXIT INT TERM
      write_status "starting-display"

      for _ in $(seq 1 50); do
        if [ -S "/tmp/.X11-unix/X$display_number" ]; then
          break
        fi
        if ! kill -0 "$xvfb_pid" 2>/dev/null; then
          echo "Xvfb exited before display $DISPLAY became ready" >&2
          exit 1
        fi
        sleep 0.1
      done
      if [ ! -S "/tmp/.X11-unix/X$display_number" ]; then
        echo "Timed out waiting for display $DISPLAY" >&2
        exit 1
      fi

      x11vnc \
        -display "$DISPLAY" \
        -localhost \
        -forever \
        -shared \
        -nopw \
        -rfbport "$vnc_port" \
        -quiet &
      x11vnc_pid=$!

      novnc \
        --listen "$novnc_listen" \
        --vnc "127.0.0.1:$vnc_port" \
        --file-only &
      novnc_pid=$!
      write_status "waiting-for-device"

      while [ "$shutting_down" -eq 0 ]; do
        adb connect "$serial" >/dev/null 2>&1 || true
        if [ "$(adb -s "$serial" get-state 2>/dev/null || true)" = "device" ] && \
          [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
          break
        fi
        sleep 2
      done

      while [ "$shutting_down" -eq 0 ]; do
        write_status "running"
        set +e
        scrcpy \
          --serial "$serial" \
          --no-audio \
          --stay-awake \
          --max-fps=30 \
          --video-bit-rate=8M \
          --window-title="Hermes Android" \
          "$@" &
        scrcpy_pid=$!
        write_status "running"
        wait "$scrcpy_pid"
        exit_code=$?
        set -e
        scrcpy_pid=
        last_exit_code=$exit_code
        if [ "$shutting_down" -eq 1 ]; then
          break
        fi
        restart_count=$((restart_count + 1))
        write_status "reconnecting"
        adb connect "$serial" >/dev/null 2>&1 || true
        sleep 2
      done
    '';
  };

  tools = pkgs.buildEnv {
    name = "hermes-browser-tools";
    paths = with pkgs; [
      android-tools
      bash
      androidViewer
      browserLauncher
      cacert
      coreutils
      curl
      gnugrep
      jq
      procps
      scrcpy
      tzdata
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
      "/share"
    ];
  };

  root = runCommand "hermes-browser-root" {} ''
    mkdir -p \
      "$out/etc" \
      "$out/opt/browser" \
      "$out/opt/hermes/extensions" \
      "$out/run/current-system/sw/share/chromium/extensions" \
      "$out/tmp"
    ln -s ${fontconfigFile} "$out/etc/fonts.conf"
    cp ${chromiumPolicy} "$out/opt/hermes/hermes-browser.json"
    cp ${ublockOriginLiteCrx} "$out/opt/hermes/extensions/ublock-origin-lite.crx"
    cp ${ublockOriginLiteExternal} \
      "$out/run/current-system/sw/share/chromium/extensions/${ublockOriginLiteId}.json"
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
        "org.opencontainers.image.description" = "Chromium and Android display sidecars for Hermes Agent";
        "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
      };
    };
  }
