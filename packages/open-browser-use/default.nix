{
  fetchurl,
  fetchzip,
  jq,
  lib,
  runCommand,
  stdenvNoCC,
}: let
  version = "0.1.41";
  extensionId = "bgjoihaepiejlfjinojjfgokghnodnhd";
  betaExtensionId = "pnbmoicbkopffjjgfgfglopechaiemkp";
  betaExtensionPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnBLT95WWVnHYH0pOBRH/eP+BWtlKVmLE/RHkERUTI2+PGDSQrbWVabmTw4CZ3yhjko04dijSX2Az8cnp65xh23Dh5mP5TCtiP9LexRFJokd8EsyeFdtKamMYr0hF1ZUc1/8ZpLnetAU65ZMB9VzHQBqpJWeUwuIvecgfRtGklDgJMjnvcq5J6pttZrzWrI/2B0BNufwsTQfEt7qLtDFPHXmUdtZfQbc2EfYFvkXLDAXicYviiocedrsAGIKUxpyQegobhUFL+tNLOuXKBpZlLFQn3xgm5CyGZwN6bueiV/S7reigVTKAMQ8BX0eacT22e8r0UzjsjkugeHOIonIvtQIDAQAB";
  chromeExtensionSource = fetchzip {
    url = "https://github.com/iFurySt/open-browser-use/releases/download/v${version}/open-browser-use-chrome-extension-${version}.zip";
    hash = "sha256-X5fwUYJ/dLe4BH4wvXUJj8zRyzHSmz1Qp5RuarmEkfU=";
    stripRoot = false;
  };
  keyedChromeExtension = runCommand "open-browser-use-chrome-extension-${version}" {nativeBuildInputs = [jq];} ''
    mkdir -p "$out"
    cp -R ${chromeExtensionSource}/. "$out/"
    chmod u+w "$out/manifest.json"
    jq --arg key ${lib.escapeShellArg betaExtensionPublicKey} \
      '.key = $key' "$out/manifest.json" > "$out/manifest.json.tmp"
    mv "$out/manifest.json.tmp" "$out/manifest.json"
  '';
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
          "chrome-extension://${extensionId}/",
          "chrome-extension://${betaExtensionId}/"
        ]
      }
      EOF

      runHook postInstall
    '';

    passthru = {
      chromeExtension = fetchurl {
        url = "https://github.com/iFurySt/open-browser-use/releases/download/v${version}/open-browser-use-chrome-extension-${version}.crx";
        hash = "sha256-E9aZBv/a4HWQG51y2EilNAGlN8hm0o9+qwjfhUc7/fk=";
      };
      chromeExtensionUnpacked = keyedChromeExtension;
    };

    meta = {
      description = "Platform-neutral browser-use CLI and MCP server";
      homepage = "https://github.com/iFurySt/open-browser-use";
      license = lib.licenses.mit;
      mainProgram = "open-browser-use";
      platforms = builtins.attrNames sources;
    };
  })
