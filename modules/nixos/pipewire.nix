{
  lib,
  isWsl,
  ...
}: {
  services.pipewire = lib.mkIf (!isWsl) {
    enable = true;
    jack.enable = true;
    pulse.enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
  };
}
