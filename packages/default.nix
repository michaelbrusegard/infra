{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
  chromium-seccomp-profile = pkgs.callPackage ./chromium-seccomp-profile {};
  stalwart-oss = pkgs.callPackage ./stalwart-oss {};
  stalwart-oss-image = pkgs.callPackage ./stalwart-oss/image.nix {};
  stalwart-native-scim = pkgs.callPackage ./stalwart-oss {nativeScim = true;};
  stalwart-native-scim-image = pkgs.callPackage ./stalwart-oss/image.nix {nativeScim = true;};
}
// {
  codex = pkgs.callPackage ./codex {};
  kimi-cli = pkgs.callPackage ./kimi-cli {};
  open-browser-use = pkgs.callPackage ./open-browser-use {};
  open-computer-use = pkgs.callPackage ./open-computer-use {};
  slack-cli = pkgs.callPackage ./slack-cli {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
