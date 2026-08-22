{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
  chromium-seccomp-profile = pkgs.callPackage ./chromium-seccomp-profile {};
}
// {
  open-browser-use = pkgs.callPackage ./open-browser-use {};
  open-computer-use = pkgs.callPackage ./open-computer-use {};
  slack-cli = pkgs.callPackage ./slack-cli {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
