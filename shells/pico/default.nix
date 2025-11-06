{ pkgs, pkgs-unstable, ... }:
let
  pico-sdk-with-submodules = pkgs-unstable.pico-sdk.override {
    withSubmodules = true;
  };
in
pkgs.mkShell {
  buildInputs = with pkgs-unstable; [
    cmake
    gcc-arm-embedded
    picotool
    pico-sdk-with-submodules
  ];
  PICO_SDK_PATH = "${pico-sdk-with-submodules}/lib/pico-sdk";
}
