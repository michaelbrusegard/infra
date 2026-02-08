{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec.lsp.servers.nixd = {
    package = pkgs.nixd;
    settings.nixd = {
      nixpkgs.expr = "import <nixpkgs> { }";
      formatting.command = ["${pkgs.alejandra}/bin/alejandra"];
    };
  };
}
