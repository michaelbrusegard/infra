{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
}
// {
  omp = pkgs.callPackage ./omp {};
  open-computer-use = pkgs.callPackage ./open-computer-use {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
