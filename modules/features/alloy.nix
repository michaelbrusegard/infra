{
  flake.modules.nixos.alloy = {
    services.alloy = {
      enable = true;
      configPath = "/etc/alloy";
    };
  };
}
