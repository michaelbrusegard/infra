{ ... }: {
  services.k3s = {
    enable = true;
    clusterInit = true;
    extraFlags = [
      "--write-kubeconfig-mode=0644"
    ];
  };
}
