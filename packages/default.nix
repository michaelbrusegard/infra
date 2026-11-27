{ pkgs }:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  ardia = pkgs.callPackage ./ardia { };
  chromium-seccomp-profile = pkgs.callPackage ./chromium-seccomp-profile { };
  helium-browser = pkgs.callPackage ./helium-browser { };
  rustdesk-flutter = pkgs.callPackage ./rustdesk { };
  stalwart-native-scim = pkgs.callPackage ./stalwart-oss { };
}
// {
  ai-images = pkgs.callPackage ./ai-images { };
  blender-mcp = pkgs.callPackage ./blender-mcp { };
  bulwark-desktop = pkgs.callPackage ./bulwark-desktop { };
  slack-cli = pkgs.callPackage ./slack-cli { };
  vite-plus = import ./vite-plus { inherit pkgs; };
}
// import ./craft-apps { inherit pkgs; }
