_: {
  services.k3s = {
    enable = true;
    clusterInit = true;
    gracefulNodeShutdown.enable = true;
    extraFlags = [
      "--write-kubeconfig-mode=0644"
    ];
  };
}
