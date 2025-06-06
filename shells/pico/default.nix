{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    cmake
    gcc-arm-embedded
    picotool
    pico-sdk
  ];
  PICO_SDK_PATH = "${pkgs.pico-sdk}";
  CC = "${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc";
  CXX = "${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-g++";
}
