{inputs, ...}: {
  services.kanata = {
    enable = true;
    keyboards.default.configFile = inputs.self + "/config/kanata/linux.kbd";
  };
}
