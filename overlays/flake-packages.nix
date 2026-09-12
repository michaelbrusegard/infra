inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
  paseoBase = inputs.paseo.packages.${system}.paseo.override {
    npmDepsHash = "sha256-TRZej2L43C3go4NWe496Dqs/4A+0GivCRtGzt3pX2dw=";
  };
  paseoElectron = inputs.paseo.inputs.nixpkgs.legacyPackages.${system}.electron;
  paseoTerminalSmoke = ../packages/paseo/terminal-worker-smoke.mjs;
  paseoPackage = paseoBase.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/paseo-terminal-native.patch];
    doInstallCheck = prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform;
    installCheckPhase = ''
      runHook preInstallCheck
      env -u NODE_PATH HOME="$TMPDIR/paseo-smoke-home" \
        ${paseoBase.nodejs}/bin/node ${paseoTerminalSmoke} "$out/lib/paseo"
      runHook postInstallCheck
    '';
  });
  paseoDesktopPackage =
    (inputs.paseo.packages.${system}.desktop.override {
      paseo = paseoPackage;
    }).overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [prev.autoPatchelfHook];
      buildInputs =
        (old.buildInputs or [])
        ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [prev.stdenv.cc.cc.lib];
      autoPatchelfIgnoreMissingDeps = ["libc.musl-x86_64.so.1"];
      patches =
        (old.patches or [])
        ++ [
          ../patches/paseo-keybinds.patch
          ../patches/paseo-fonts.patch
          ../patches/paseo-full-access-mcp-elicitations.patch
          ../patches/paseo-terminal-native.patch
        ];
      # Darwin's app bundle uses electron-builder rather than the runtime trace.
      doInstallCheck = prev.stdenv.hostPlatform.isLinux && prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform;
      installCheckPhase = ''
        runHook preInstallCheck
        env -u NODE_PATH HOME="$TMPDIR/paseo-smoke-home" ELECTRON_RUN_AS_NODE=1 \
          ${paseoElectron}/bin/electron ${paseoTerminalSmoke} "$out/share/paseo-desktop"
        runHook postInstallCheck
      '';
    });
in {
  inherit (inputs.hyprland.packages.${system}) hyprland xdg-desktop-portal-hyprland;

  quickshell = inputs.quickshell.packages.${system}.default;
  dms-shell = inputs.dms.packages.${system}.default;
  dms-greeter = inputs.dms.packages.${system}.default;
  dsearch = inputs.dsearch.packages.${system}.default;
  paseo = paseoPackage;
  paseo-desktop = paseoDesktopPackage;
}
