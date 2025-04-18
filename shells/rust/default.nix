{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    rustup
  ];
}
