{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
  chatgpt-desktop = pkgs.callPackage ./chatgpt-desktop {};
  chromium-seccomp-profile = pkgs.callPackage ./chromium-seccomp-profile {};
  rustdesk-flutter = pkgs.callPackage ./rustdesk {};
  smtp-edge-image = pkgs.callPackage ./smtp-edge/image.nix {};
  stalwart-oss = pkgs.callPackage ./stalwart-oss {};
  stalwart-oss-image = pkgs.callPackage ./stalwart-oss/image.nix {};
  stalwart-native-scim = pkgs.callPackage ./stalwart-oss {nativeScim = true;};
  stalwart-native-scim-image = pkgs.callPackage ./stalwart-oss/image.nix {nativeScim = true;};
}
// {
  codex = pkgs.callPackage ./codex {};
  opencode = pkgs.callPackage ./opencode {};
  pi-coding-agent = pkgs.callPackage ./pi-coding-agent {};
  pi-cliproxyapi-provider = pkgs.callPackage ./pi-cliproxyapi-provider {};
  slack-cli = pkgs.callPackage ./slack-cli {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
