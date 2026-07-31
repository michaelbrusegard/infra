{
  fetchurl,
  lib,
  stdenvNoCC,
}: let
  version = "0.1.41";
  extensionId = "bgjoihaepiejlfjinojjfgokghnodnhd";
  system = stdenvNoCC.hostPlatform.system;
  sources = {
    x86_64-linux = {
      platform = "linux-amd64";
      hash = "sha256-q73oHFDVT8PoWN2BLwqGA+VWzZuRXqBTArnoE1vUliI=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-hFWjdG2gH77hg3XmbosQ0Hhvx3VexXrmNYaoOx74sUU=";
    };
    x86_64-darwin = {
      platform = "darwin-amd64";
      hash = "sha256-WryE1X4a4+bj1VilyqVR5w5LARByjB3fe8jIQEkBT4Q=";
    };
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-nz4PH9NJ97bnGju6WeUNYcf8ABcvUGT7uoF2TL2mXVY=";
    };
  };
  source = sources.${system} or (throw "open-browser-use: unsupported system ${system}");
in
  stdenvNoCC.mkDerivation (_finalAttrs: {
    pname = "open-browser-use";
    inherit version;

    src = fetchurl {
      url = "https://github.com/iFurySt/open-browser-use/releases/download/v${version}/open-browser-use-cli-${version}-${source.platform}.tar.gz";
      inherit (source) hash;
    };

    sourceRoot = ".";
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 open-browser-use "$out/bin/open-browser-use"
      ln -s open-browser-use "$out/bin/obu"

      install -d "$out/etc/chromium/native-messaging-hosts"
      cat > "$out/etc/chromium/native-messaging-hosts/com.ifuryst.open_browser_use.extension.json" <<EOF
      {
        "name": "com.ifuryst.open_browser_use.extension",
        "description": "Open Browser Use Chrome native messaging host",
        "path": "$out/bin/open-browser-use",
        "type": "stdio",
        "allowed_origins": [
          "chrome-extension://${extensionId}/"
        ]
      }
      EOF

      runHook postInstall
    '';

    passthru.chromeExtension = fetchurl {
      url = "https://github.com/iFurySt/open-browser-use/releases/download/v${version}/open-browser-use-chrome-extension-${version}.crx";
      hash = "sha256-E9aZBv/a4HWQG51y2EilNAGlN8hm0o9+qwjfhUc7/fk=";
    };

    meta = {
      description = "Platform-neutral browser-use CLI and MCP server";
      homepage = "https://github.com/iFurySt/open-browser-use";
      license = lib.licenses.mit;
      mainProgram = "open-browser-use";
      platforms = builtins.attrNames sources;
    };
  })
