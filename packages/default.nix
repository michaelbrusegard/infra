{pkgs}: {
  betterbird = pkgs.callPackage ./betterbird {};
  vite-plus = import ./vite-plus {inherit pkgs;};
}
