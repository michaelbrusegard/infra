{config, ...}: {
  services.k3s = {
    enable = true;
    gracefulNodeShutdown.enable = true;
    nodeName = config.networking.hostName;
    extraFlags = [
      "--write-kubeconfig-mode=0644"
    ];
    disable = [
      "traefik"
      "servicelb"
      "local-storage"
    ];
  };
}
