{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    jdk21
    gradle
    xorg.libXxf86vm
    libGL
    alsaLib
    openal
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.libGL
    pkgs.xorg.libXxf86vm
    pkgs.alsaLib
    pkgs.openal
  ];
}
