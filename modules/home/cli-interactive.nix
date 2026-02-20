{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs;
    [
      yq
      screen
      lsof
      carbon-now-cli
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      psmisc
      wf-recorder
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      iproute2mac
    ];
}
