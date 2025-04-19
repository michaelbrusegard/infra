{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    rustup
    rust-analyzer
  ];
}
