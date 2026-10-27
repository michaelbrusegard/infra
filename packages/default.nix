{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  chromium-seccomp-profile = pkgs.callPackage ./chromium-seccomp-profile {};
  rustdesk-flutter = pkgs.callPackage ./rustdesk {};
  smtp-edge-image = pkgs.callPackage ./smtp-edge/image.nix {};
  stalwart-oss = pkgs.callPackage ./stalwart-oss {};
  stalwart-oss-image = pkgs.callPackage ./stalwart-oss/image.nix {};
  stalwart-native-scim = pkgs.callPackage ./stalwart-oss {nativeScim = true;};
  stalwart-native-scim-image = pkgs.callPackage ./stalwart-oss/image.nix {nativeScim = true;};
}
// pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  openbubbles = pkgs.callPackage ./openbubbles {};
}
// {
  ai-images = pkgs.callPackage ./ai-images {};
  slack-cli = pkgs.callPackage ./slack-cli {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
