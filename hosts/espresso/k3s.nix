{config}: {
  services.k3s = {
    enable = true;
    clusterInit = config.networking.hostName == "espresso-0";
    gracefulNodeShutdown.enable = true;
    inherit (config.secrets.services.k3s) tokenFile;
    extraFlags = [
      "--write-kubeconfig-mode=0644"
    ];
  };
}
