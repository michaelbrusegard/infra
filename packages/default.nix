{pkgs}: {
  google-sans-flex = import ./google-sans-flex.nix {inherit pkgs;};
  google-sans-code = import ./google-sans-code.nix {inherit pkgs;};
}
