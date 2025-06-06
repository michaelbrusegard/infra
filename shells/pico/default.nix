{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    cmake
    gcc-arm-embedded
    picotool
    pico-sdk
  ];
}
