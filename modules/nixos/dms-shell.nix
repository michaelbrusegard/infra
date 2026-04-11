{inputs, ...}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
        builtins.removeAttrs
        (import "${inputs.nixpkgs-unstable}/nixos/modules/programs/wayland/dms-shell.nix" {inherit config lib pkgs;})
        ["meta"]
    )
  ];

  programs.dms-shell = {
    enable = true;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    enableSystemMonitoring = true;
    enableVPN = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;
  };
}
