{pkgs}:
pkgs.appimageTools.wrapType2 {
  pname = "breaktimer";
  version = "2.0.1";

  src = pkgs.fetchurl {
    url = "https://github.com/tom-james-watson/breaktimer-app/releases/download/v2.0.1/BreakTimer.AppImage";
    hash = "sha256-FTOy3oBzQTyKTdxihS5Ua1VB4YlxrQMk6kenNp4hTzY=";
  };

  extraInstallCommands = ''
    install -Dm444 ${pkgs.makeDesktopItem {
      name = "breaktimer";
      desktopName = "BreakTimer";
      exec = "breaktimer %U";
      icon = "breaktimer";
      categories = ["Utility"];
    }}/share/applications/*.desktop \
      $out/share/applications/breaktimer.desktop
  '';
}
