{ pkgs, ... }:
let
  pico-sdk-with-submodules = pkgs.pico-sdk.override {
    withSubmodules = true;
  };
in
pkgs.mkShell {
  name = "pico-dev";
  buildInputs = with pkgs; [
    cmake
    gcc-arm-embedded
    picotool
    pico-sdk-with-submodules
  ];
  PICO_SDK_PATH = "${pico-sdk-with-submodules}/lib/pico-sdk";
  CC = "${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc";
  CXX = "${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-g++";
}
