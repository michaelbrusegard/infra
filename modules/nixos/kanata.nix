{
  lib,
  inputs,
  isWsl,
  ...
}: {
  services.kanata = lib.mkIf (!isWsl) {
    enable = true;
    keyboards.default.configFile = inputs.self + "/config/kanata/linux.kbd";
  };
}
