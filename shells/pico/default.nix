{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    cmake
    gcc-arm-embedded-13
    picotool
  ];
}
