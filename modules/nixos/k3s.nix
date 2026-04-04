{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.kubernetes-helm];

  services.k3s = {
    enable = true;
    gracefulNodeShutdown.enable = true;
    nodeName = config.networking.hostName;
    extraFlags = [
      "--write-kubeconfig-mode=0644"
      "--disable-kube-proxy"
      "--disable-network-policy"
      "--flannel-backend=none"
      "--node-label=openebs.io/engine=mayastor"
    ];
    disable = [
      "traefik"
      "servicelb"
      "local-storage"
      "metrics-server"
    ];
  };
}
