{pkgs}:
pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  betterbird = pkgs.callPackage ./betterbird {};
}
// {
  vite-plus = import ./vite-plus {inherit pkgs;};
}
