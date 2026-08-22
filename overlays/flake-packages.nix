inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
  paseoPackage = inputs.paseo.packages.${system}.paseo.override {
    npmDepsHash = "sha256-i5PbVUe2Ec+GtghV9IpCJQJ9hcUT5hFhmxneNvoD584=";
  };
  paseoDesktopPackage =
    (inputs.paseo.packages.${system}.desktop.override {
      paseo = paseoPackage;
    }).overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [prev.autoPatchelfHook];
      buildInputs =
        (old.buildInputs or [])
        ++ [prev.stdenv.cc.cc.lib];
      autoPatchelfIgnoreMissingDeps = ["libc.musl-x86_64.so.1"];
      patches =
        (old.patches or [])
        ++ [
          ../patches/paseo-keybinds.patch
          ../patches/paseo-fonts.patch
          ../patches/paseo-full-access-mcp-elicitations.patch
        ];
    });
in
  {
    inherit (inputs.hyprland.packages.${system}) hyprland xdg-desktop-portal-hyprland;

    quickshell = inputs.quickshell.packages.${system}.default;
    dms-shell = inputs.dms.packages.${system}.default;
    dms-greeter = inputs.dms.packages.${system}.default;
    dsearch = inputs.dsearch.packages.${system}.default;
    paseo = paseoPackage;
  }
  // prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
    paseo-desktop = paseoDesktopPackage;
  }
