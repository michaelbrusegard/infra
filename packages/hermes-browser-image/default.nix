{
  dockerTools,
  pkgs,
  runCommand,
}:
let
  ublockOriginLiteId = "ddkjiahejlhfcafbddmgiahcphecmpfh";
  ublockOriginLiteVersion = "2026.820.1159";
  ublockOriginLiteCrx = pkgs.fetchurl {
    url = "https://clients2.googleusercontent.com/crx/blobs/Abe5cL6jgS7UbQLqrOGJVZfqnpyWC5zn5nRV8xCUDS7yyvZrP9tuSCLz7BA-Drzn0iJ8GA_MvO4e0CJ-Rhd9rD6_5I03LdpaB7C-Y1HDKaNcvq9598BEIfoE4nFT68I1_nm5AMZSmuVfu8goBvj3Em6oiQCK-5QL1fHNTg/DDKJIAHEJLHFCAFBDDMGIAHCPHECMPFH_2026_820_1159_0.crx";
    hash = "sha256-fBzFyuzCdxv3NW0RJTIu/1wxNSFFr/pCVtfdZnWZTAs=";
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
  novncDefaults = pkgs.writeText "defaults.json" "{}";
  novncMandatory = pkgs.writeText "mandatory.json" (
    builtins.toJSON {
      autoconnect = true;
      reconnect = true;
      resize = "scale";
      view_only = false;
    }
  );
  novncWeb = runCommand "hermes-novnc-web" { } ''
    cp -r ${pkgs.novnc}/share/webapps/novnc "$out"
    chmod -R u+w "$out"
    cp ${novncDefaults} "$out/defaults.json"
    cp ${novncMandatory} "$out/mandatory.json"
  '';

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
        "external_extension_count": ''${external_extension_count:-0},
        "unpacked_extension_count": ''${unpacked_extension_count:-0},
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
      external_extension_count=0
      unpacked_extension_count=0
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
        --web ${novncWeb} \
        --file-only &
      novnc_pid=$!

      managed_policy_dir=/etc/chromium/policies/managed
      mkdir -p "$managed_policy_dir"
      find "$managed_policy_dir" -maxdepth 1 -type f -name '*.json' -delete
      install -m 0644 "$HERMES_BROWSER_POLICY_TEMPLATE" \
        "$managed_policy_dir/hermes-browser.json"
      if [ -d /opt/browser/policies/managed ]; then
        find /opt/browser/policies/managed -maxdepth 1 -type f -name '*.json' \
          -exec install -m 0644 {} "$managed_policy_dir/" \;
      fi
      managed_policy_count=$(find "$managed_policy_dir" -maxdepth 1 -type f -name '*.json' | wc -l)

      extra_args=()
      extension_dirs=()
      external_extension_dir=/run/current-system/sw/share/chromium/extensions
      if [ -d "$external_extension_dir" ]; then
        external_extension_count=$(
          find "$external_extension_dir" -maxdepth 1 -name '*.json' \
            \( -type f -o -type l \) | wc -l
        )
      fi
      if [ -d /opt/browser/extensions-unpacked ]; then
        while IFS= read -r manifest; do
          extension_dirs+=("$(dirname "$manifest")")
        done < <(
          find /opt/browser/extensions-unpacked -mindepth 2 -maxdepth 2 \
            -type f -name manifest.json | sort
        )
      fi
      unpacked_extension_count=''${#extension_dirs[@]}
      extension_count=$((external_extension_count + unpacked_extension_count))
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
        ${pkgs.chromium}/bin/chromium \
          --disable-setuid-sandbox \
          "$@" "''${extra_args[@]}" &
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
    runtimeInputs = [ pkgs.novnc ];
    text = ''
      exec novnc \
        --listen "''${ANDROID_VIEW_LISTEN:-0.0.0.0:6081}" \
        --vnc "''${ANDROID_VIEW_VNC:-127.0.0.1:5900}" \
        --web ${novncWeb} \
        --file-only
    '';
  };

  tools = pkgs.buildEnv {
    name = "hermes-browser-tools";
    paths = with pkgs; [
      bash
      androidViewer
      browserLauncher
      cacert
      coreutils
      curl
      gnugrep
      jq
      procps
      tzdata
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
      "/share"
    ];
  };

  root = runCommand "hermes-browser-root" { } ''
    mkdir -p \
      "$out/etc/chromium/policies/managed" \
      "$out/opt/browser" \
      "$out/opt/browser-files" \
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
  '';
in
dockerTools.buildLayeredImage {
  name = "ghcr.io/michaelbrusegard/hermes-browser";
  tag = "nix";
  contents = [
    tools
    root
  ];
  fakeRootCommands = ''
    chown 10000:10000 \
      ./etc/chromium/policies/managed \
      ./opt/browser \
      ./opt/browser-files
    chmod 0755 \
      ./etc/chromium/policies/managed \
      ./opt/browser \
      ./opt/browser-files
    chmod 1777 ./tmp
  '';
  config = {
    Entrypoint = [ "${browserLauncher}/bin/chromium" ];
    Env = [
      "HOME=/opt/browser"
      "PATH=${tools}/bin"
      "FONTCONFIG_FILE=/etc/fonts.conf"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "TZ=America/Los_Angeles"
      "TZDIR=${pkgs.tzdata}/share/zoneinfo"
      "LANG=en_US.UTF-8"
    ];
    User = "10000:10000";
    WorkingDir = "/opt/browser";
    Labels = {
      "org.opencontainers.image.description" = "Chromium and Android display sidecars for Hermes Agent";
      "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
    };
  };
}
