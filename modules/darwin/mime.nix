{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.duti
  ];

  system.activationScripts.setMimeDefaults.text = ''
    duti -s org.pwmt.zathura .pdf all
    duti -s com.github.everest-imv imv.png .png all
    duti -s com.github.everest-imv imv.jpg .jpg all
    duti -s com.github.everest-imv imv.jpeg .jpeg all
    duti -s io.mpv mpv.mp4 .mp4 all
  '';
}
