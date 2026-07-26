inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
  paseoPackage = inputs.paseo.packages.${system}.paseo.override {
    npmDepsHash = "sha256-DL1LamUyFzJOkPYR7eeIefGhzP/mcWGO5oxld/Bt8n0=";
  };
  t3codePackage = inputs.t3code.packages.${system}.t3-code;
in
  {
    inherit (inputs.hyprland.packages.${system}) hyprland xdg-desktop-portal-hyprland;

    quickshell = inputs.quickshell.packages.${system}.default;
    dms-shell = inputs.dms.packages.${system}.default;
    dms-greeter = inputs.dms.packages.${system}.default;
    dsearch = inputs.dsearch.packages.${system}.default;
    wezterm = inputs.wezterm.packages.${system}.default;
    paseo = paseoPackage;
    t3code =
      if prev.stdenv.hostPlatform.isLinux
      then
        t3codePackage.overrideAttrs (old: {
          postFixup =
            (old.postFixup or "")
            + ''
              wrapProgram $out/bin/t3-code --add-flags --no-sandbox
            '';
        })
      else t3codePackage;
  }
  // prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
    paseo-desktop = inputs.paseo.packages.${system}.desktop.override {
      paseo = paseoPackage;
    };
  }
