{ pkgs }:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  chromium-seccomp-profile = pkgs.callPackage ./chromium-seccomp-profile { };
  helium-browser = pkgs.callPackage ./helium-browser { };
  rustdesk-flutter = pkgs.callPackage ./rustdesk { };
  smtp-edge-image = pkgs.callPackage ./smtp-edge/image.nix { };
  stalwart-native-scim = pkgs.callPackage ./stalwart-oss { };
  stalwart-native-scim-image = pkgs.callPackage ./stalwart-oss/image.nix { };
  terraform-provider-stalwart-image = pkgs.callPackage ./terraform-provider-stalwart/image.nix { };
}
// {
  ai-images = pkgs.callPackage ./ai-images { };
  blender-mcp = pkgs.callPackage ./blender-mcp { };
  bulwark-desktop = pkgs.callPackage ./bulwark-desktop { };
  slack-cli = pkgs.callPackage ./slack-cli { };
  terraform-provider-stalwart = pkgs.callPackage ./terraform-provider-stalwart { };
  vite-plus = import ./vite-plus { inherit pkgs; };
}
// import ./craft-apps { inherit pkgs; }
