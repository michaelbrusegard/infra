{inputs, ...}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    (
      args:
        builtins.removeAttrs
        (import "${inputs.nixpkgs-unstable}/nixos/modules/programs/wayland/dms-shell.nix" args)
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
