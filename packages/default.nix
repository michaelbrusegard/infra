{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
  handy = pkgs.callPackage ./handy {};
}
// {
  omp = pkgs.callPackage ./omp {};
  open-browser-use = pkgs.callPackage ./open-browser-use {};
  open-computer-use = pkgs.callPackage ./open-computer-use {};
  slack-cli = pkgs.callPackage ./slack-cli {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
