_: {
  services.kanata = {
    enable = true;
    keyboards.default = {
      configFile = ../../config/kanata/linux.kbd;
      # TCP server (localhost) so the game-mode watcher can switch to the
      # nomods layer while gaming. Harmless when unused.
      port = 5829;
    };
  };
}
