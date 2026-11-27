{
  # Only the device permissions: the keyboard is configured from the browser
  # at wootility.io, which needs them for WebHID.
  flake.modules.nixos.wooting = { pkgs, ... }: {
    services.udev.packages = [ pkgs.wooting-udev-rules ];
  };
}
