{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs;
    [
      yq
      sd
      screen
      lsof
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      psmisc
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      iproute2mac
    ];
}
