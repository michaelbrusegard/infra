{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
}
// {
  open-browser-use = pkgs.callPackage ./open-browser-use {};
  open-computer-use = pkgs.callPackage ./open-computer-use {};
  slack-cli = pkgs.callPackage ./slack-cli {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
