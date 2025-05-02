{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    jdk21
    gradle
    xorg.libXxf86vm
    libGL
  ];

  ${if !pkgs.stdenv.isDarwin then "LD_LIBRARY_PATH" else null} = pkgs.lib.makeLibraryPath [
    pkgs.libGL
    pkgs.xorg.libXxf86vm
  ];
}
