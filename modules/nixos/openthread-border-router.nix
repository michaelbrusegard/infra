_: {
  services.matter-server.enable = true;
  services.openthread-border-router = {
    enable = true;
    backboneInterfaces = ["end0"];
    rest.listenAddress = "0.0.0.0";
    web.listenAddress = "0.0.0.0";
  };
}
