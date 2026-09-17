{config, ...}: {
  services.k3s = {
    enable = true;
    gracefulNodeShutdown.enable = true;
    nodeName = config.networking.hostName;
    # Kubelet only collects images under disk pressure, so digests that no
    # container references pile up indefinitely while the node sits below the
    # threshold. Expire them by age as well; imageMaximumGCAge has no kubelet
    # flag, so it has to come through the config file.
    extraKubeletConfig = {
      imageMinimumGCAge = "24h";
      imageMaximumGCAge = "168h";
      imageGCHighThresholdPercent = 75;
      imageGCLowThresholdPercent = 60;
    };
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

  environment.persistence."/persistent".directories = [
    "/var/lib/rancher/k3s"
    "/var/local/openebs"
  ];
}
