inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
  paseoPackage = inputs.paseo.packages.${system}.paseo.override {
    npmDepsHash = "sha256-TRZej2L43C3go4NWe496Dqs/4A+0GivCRtGzt3pX2dw=";
  };
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
        ];
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
