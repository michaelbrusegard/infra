{ pkgs }:
let
  inherit (pkgs) lib stdenv;
  inherit (stdenv.hostPlatform) isDarwin system;

  sources = lib.importJSON ./sources.json;
  apps = removeAttrs sources [ "artcraft-launcher" ];
  launcher = sources.artcraft-launcher;

  release =
    repo: version: file:
    "https://github.com/${repo}/releases/download/v${version}/${file}";

  meta = repo: mainProgram: {
    homepage = "https://github.com/${repo}";
    license = lib.licenses.asl20;
    inherit mainProgram;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };

  # The binaries link little more than libc and open the display, graphics and
  # audio libraries by name at run time.
  runtimeLibraries = with pkgs; [
    alsa-lib
    fontconfig
    libGL
    libxkbcommon
    vulkan-loader
    wayland
    libx11
    libxcursor
    libxi
    libxrandr
  ];

  linuxApp =
    pname:
    {
      repo,
      version,
      hash,
      ...
    }:
    stdenv.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl {
        url = release repo version "${pname}-${version}-linux-x86_64.tar.gz";
        inherit hash;
      };

      nativeBuildInputs = [
        pkgs.autoPatchelfHook
        pkgs.makeWrapper
      ];
      buildInputs = runtimeLibraries ++ [ stdenv.cc.cc.lib ];

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r bin share $out/
        runHook postInstall
      '';

      postFixup = ''
        for program in $out/bin/*; do
          wrapProgram "$program" \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries}
        done
      '';

      meta = meta repo pname // {
        platforms = [ "x86_64-linux" ];
      };
    };

  # The Homebrew casks install the windows only; the headless tools ship apart.
  darwinCli =
    app:
    {
      repo,
      version,
      cliHash,
      ...
    }:
    lib.nameValuePair "${app}-cli" (
      stdenv.mkDerivation {
        pname = "${app}-cli";
        inherit version;

        src = pkgs.fetchurl {
          url = release repo version "${app}-cli-${version}-macos-universal.zip";
          hash = cliHash;
        };

        nativeBuildInputs = [ pkgs.unzip ];

        installPhase = ''
          runHook preInstall
          install -Dm755 ${app}-cli $out/bin/${app}-cli
          runHook postInstall
        '';

        # Signed and notarized upstream; any rewrite would break that.
        dontFixup = true;

        meta = meta repo "${app}-cli" // {
          platforms = lib.platforms.darwin;
        };
      }
    );

  # One MCP server in front of every app, shipped only inside the launcher.
  # The launcher itself is left out: it would update the apps behind Nix.
  gateway = stdenv.mkDerivation {
    pname = "craft-ai-mcp";
    inherit (launcher) version;

    src = pkgs.fetchurl (
      if isDarwin then
        {
          url =
            release launcher.repo launcher.version
              "artcraft-launcher-${launcher.version}-macos-universal.dmg";
          hash = launcher.dmgHash;
        }
      else
        {
          url =
            release launcher.repo launcher.version
              "artcraft-launcher-${launcher.version}-linux-x86_64.tar.gz";
          inherit (launcher) hash;
        }
    );

    nativeBuildInputs = if isDarwin then [ pkgs._7zz ] else [ pkgs.autoPatchelfHook ];
    buildInputs = lib.optionals (!isDarwin) [ stdenv.cc.cc.lib ];

    unpackPhase = lib.optionalString isDarwin ''
      7zz x -y "$src" '*/ArtCraft Launcher.app/Contents/MacOS/craft-ai-mcp' >/dev/null
    '';
    sourceRoot = lib.optionalString isDarwin ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 "$(find . -name craft-ai-mcp -type f | head -1)" $out/bin/craft-ai-mcp
      runHook postInstall
    '';

    dontFixup = isDarwin;

    meta = meta launcher.repo "craft-ai-mcp";
  };
in
if system == "x86_64-linux" then
  lib.mapAttrs linuxApp apps // { craft-ai-mcp = gateway; }
else if isDarwin then
  lib.mapAttrs' darwinCli apps // { craft-ai-mcp = gateway; }
else
  { }
