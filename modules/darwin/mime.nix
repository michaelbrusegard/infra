{ pkgs, lib, ... }:

{
  home.packages = [
    pkgs.duti
  ];

  home.activation.setMimeDefaults =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      duti -s org.pwmt.zathura .pdf all
      duti -s com.github.everest-imv imv.png .png all
      duti -s com.github.everest-imv imv.jpg .jpg all
      duti -s com.github.everest-imv imv.jpeg .jpeg all
      duti -s io.mpv mpv.mp4 .mp4 all
    '';
}
