{
  dockerTools,
  pkgs,
  runCommand,
}: let
  androidEmulatorContainerScripts = pkgs.fetchFromGitHub {
    owner = "google";
    repo = "android-emulator-container-scripts";
    rev = "0654f694b46794fae4b178f1e1a17cb60c5d2d34";
    sha256 = "1l3yqphfcl6z6pb6xflwf9sfzw9679jh98r90s5d8hl23kbmgxrl";
  };
  androidViewerLogger = pkgs.writeText "android-viewer-logger.ts" ''
    const logger = {
      setLevel: (_level: string) => undefined,
      trace: (...args: unknown[]) => console.debug(...args),
      debug: (...args: unknown[]) => console.debug(...args),
      info: (...args: unknown[]) => console.info(...args),
      warn: (...args: unknown[]) => console.warn(...args),
      error: (...args: unknown[]) => console.error(...args),
    };

    export default logger;
  '';
  androidWebrtcFrontend = pkgs.buildNpmPackage {
    pname = "hermes-android-webrtc-frontend";
    version = "2.0.0-0654f69";
    src = androidEmulatorContainerScripts;
    sourceRoot = "${androidEmulatorContainerScripts.name}/js/example";
    npmDepsHash = "sha256-7oIAKHGIpntx7+LBiwDJYXXlVDPCvXSFEVAe6ck85nA=";
    nativeBuildInputs = with pkgs; [
      protobuf
      protoc-gen-js
    ];
    postPatch = ''
      cp -r ../src ./lib
      chmod -R u+w ./lib
      cp ${./android-viewer-app.tsx} ./src/App.tsx
      cp ${androidViewerLogger} ./lib/components/emulator/net/logger.ts
      substituteInPlace ./index.html \
        --replace-fail "<title>Android Emulator WebRTC Demo</title>" "<title>Hermes Android</title>"
      substituteInPlace ./vite.config.js \
        --replace-fail "base: '/android-emulator-webrtc/'," "base: '/'," \
        --replace-fail "/src\\/proto/" "/lib\\/proto/"
    '';
    preBuild = ''
      protoc \
        -I ../proto \
        --plugin=protoc-gen-js=${pkgs.protoc-gen-js}/bin/protoc-gen-js \
        --js_out=import_style=commonjs,binary:./lib/proto \
        ../proto/emulator_controller.proto
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r dist/. "$out/"
      runHook postInstall
    '';
  };
  androidWebrtcGateway = runCommand "hermes-android-webrtc-gateway-source" {} ''
    mkdir -p "$out/videobridge_gateway"
    cp \
      ${androidEmulatorContainerScripts}/gateway/src/videobridge_gateway/gateway_server.py \
      "$out/videobridge_gateway/gateway_server.py"
    chmod u+w "$out/videobridge_gateway/gateway_server.py"
    patch -d "$out/videobridge_gateway" -p1 < ${./android-viewer-gateway.patch}
    substituteInPlace "$out/videobridge_gateway/gateway_server.py" \
      --replace-fail 'web.TCPSite(runner, "0.0.0.0", args.port)' 'web.TCPSite(runner, "127.0.0.1", args.port)' \
      --replace-fail 'Gateway Webserver listening on http://0.0.0.0:' 'Gateway Webserver listening on http://127.0.0.1:'
    touch "$out/videobridge_gateway/__init__.py"
  '';
  androidWebrtcPython = pkgs.python3.withPackages (pythonPackages:
    with pythonPackages; [
      aiohttp
      grpcio
      grpcio-tools
      protobuf
      websockets
    ]);
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
  novncDefaults = pkgs.writeText "defaults.json" "{}";
  novncMandatory = pkgs.writeText "mandatory.json" (
    builtins.toJSON {
      autoconnect = true;
      reconnect = true;
      resize = "scale";
      view_only = false;
    }
  );
  novncWeb = runCommand "hermes-novnc-web" {} ''
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
      androidWebrtcPython
      chromium
      coreutils
      curl
      gnugrep
      novnc
      procps
      x11vnc
      xkbcomp
      xkeyboard_config
      xorg-server
    ];
    text = ''
      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        echo "Usage: android-viewer [Chromium options...]"
        echo "Streams the emulator framebuffer through WebRTC and serves it over noVNC."
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
      grpc_token_file="''${ANDROID_EMULATOR_GRPC_TOKEN_FILE:-/opt/android/companion/emulator-grpc-token}"
      grpc_proto_dir="''${ANDROID_EMULATOR_GRPC_PROTO_DIR:-/opt/android/companion}"
      gateway_root="$HOME/webrtc-gateway"
      discovery_file="$gateway_root/emulator-discovery.ini"
      restart_count=0
      last_exit_code=null
      backend=emulator-webrtc
      gateway_pid=
      web_pid=
      viewer_pid=
      x11vnc_pid=
      novnc_pid=
      shutting_down=0

      mkdir -p "$HOME" "$supervisor_dir" "$gateway_root" /tmp/.X11-unix
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
        "backend": "$(json_escape "$backend")",
        "serial": "$(json_escape "$serial")",
        "display": "$(json_escape "$DISPLAY")",
        "novnc_listen": "$(json_escape "$novnc_listen")",
        "xvfb_pid": ''${xvfb_pid:-null},
        "x11vnc_pid": ''${x11vnc_pid:-null},
        "novnc_pid": ''${novnc_pid:-null},
        "gateway_pid": ''${gateway_pid:-null},
        "web_pid": ''${web_pid:-null},
        "viewer_pid": ''${viewer_pid:-null},
        "secure_capture": true,
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
        for pid in "$viewer_pid" "$web_pid" "$gateway_pid" "$novnc_pid" "$x11vnc_pid" "$xvfb_pid"; do
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
        --web ${novncWeb} \
        --file-only &
      novnc_pid=$!
      write_status "waiting-for-emulator"
      for _ in $(seq 1 60); do
        if [ -s "$grpc_token_file" ] && \
          [ -s "$grpc_proto_dir/emulator_controller.proto" ] && \
          [ -s "$grpc_proto_dir/rtc_service_v2.proto" ] && \
          [ -s "$grpc_proto_dir/ice_config.proto" ]; then
          break
        fi
        sleep 1
      done
      if [ ! -s "$grpc_token_file" ]; then
        echo "Timed out waiting for emulator gRPC token: $grpc_token_file" >&2
        exit 1
      fi

      rm -rf "$gateway_root/videobridge_gateway"
      cp -r ${androidWebrtcGateway}/videobridge_gateway "$gateway_root/"
      chmod -R u+w "$gateway_root/videobridge_gateway"
      mkdir -p "$gateway_root/videobridge_gateway/proto"
      touch "$gateway_root/videobridge_gateway/proto/__init__.py"
      ${androidWebrtcPython}/bin/python -m grpc_tools.protoc \
        -I "$grpc_proto_dir" \
        --python_out="$gateway_root/videobridge_gateway/proto" \
        --grpc_python_out="$gateway_root/videobridge_gateway/proto" \
        "$grpc_proto_dir/emulator_controller.proto" \
        "$grpc_proto_dir/rtc_service_v2.proto" \
        "$grpc_proto_dir/ice_config.proto"

      while [ "$shutting_down" -eq 0 ]; do
        token=$(tr -d '\r\n' <"$grpc_token_file")
        if [ -z "$token" ]; then
          echo "Emulator gRPC token is empty: $grpc_token_file" >&2
          exit 1
        fi
        cat >"$discovery_file" <<EOF
      grpc.port=8554
      grpc.token=$token
      EOF

        PYTHONPATH="$gateway_root" ${androidWebrtcPython}/bin/python \
          -m videobridge_gateway.gateway_server \
          --port=8080 \
          --discovery_file="$discovery_file" \
          --videobridge_token="$token" &
        gateway_pid=$!
        ${androidWebrtcPython}/bin/python \
          -m http.server 8081 \
          --bind 127.0.0.1 \
          --directory ${androidWebrtcFrontend} &
        web_pid=$!

        services_ready=0
        for _ in $(seq 1 60); do
          if curl --fail --silent http://127.0.0.1:8080/api/v1/emulator/status | grep -q '"booted": true' && \
            curl --fail --silent http://127.0.0.1:8081/ >/dev/null; then
            services_ready=1
            break
          fi
          if ! kill -0 "$gateway_pid" 2>/dev/null || ! kill -0 "$web_pid" 2>/dev/null; then
            break
          fi
          sleep 1
        done
        if [ "$services_ready" -ne 1 ]; then
          echo "Android WebRTC viewer services failed to become ready" >&2
          exit 1
        fi

        ${pkgs.chromium}/bin/chromium \
          --app=http://127.0.0.1:8081/ \
          --kiosk \
          --no-sandbox \
          --ozone-platform=x11 \
          --window-position=0,0 \
          --window-size=1080,1920 \
          --force-device-scale-factor=1 \
          --autoplay-policy=no-user-gesture-required \
          --use-gl=angle \
          --use-angle=swiftshader-webgl \
          --enable-unsafe-swiftshader \
          --disable-component-update \
          --disable-default-apps \
          --disable-features=Translate \
          --hide-scrollbars \
          --no-first-run \
          --no-default-browser-check \
          --remote-debugging-port=9223 \
          --user-data-dir="$HOME/chromium-profile" \
          "$@" &
        viewer_pid=$!
        write_status "running"

        set +e
        while kill -0 "$viewer_pid" 2>/dev/null && \
          kill -0 "$gateway_pid" 2>/dev/null && \
          kill -0 "$web_pid" 2>/dev/null; do
          sleep 2
        done
        for pid in "$viewer_pid" "$web_pid" "$gateway_pid"; do
          kill -TERM "$pid" 2>/dev/null || true
        done
        wait "$viewer_pid"
        exit_code=$?
        wait "$web_pid" "$gateway_pid" 2>/dev/null || true
        set -e
        viewer_pid=
        web_pid=
        gateway_pid=
        last_exit_code=$exit_code
        if [ "$shutting_down" -eq 1 ]; then
          break
        fi
        restart_count=$((restart_count + 1))
        write_status "reconnecting"
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
