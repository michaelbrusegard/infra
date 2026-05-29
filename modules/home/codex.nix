{pkgs, ...}: {
  programs.codex.enable = true;
  home.packages = with pkgs;
    lib.optionals pkgs.stdenv.isDarwin [
      brewCasks.codex-app
    ];
}
