{
  config,
  lib,
  ...
}: {
  services.k3s = {
    enable = true;
    clusterInit = config.networking.hostName == "espresso-0";
    serverAddr =
      lib.mkIf
      (config.networking.hostName != "espresso-0")
      "https://10.0.168.18:6443";
    gracefulNodeShutdown.enable = true;
    inherit (config.secrets.services.k3s) tokenFile;
    extraFlags = [
      "--write-kubeconfig-mode=0644"
      "--disable=traefik"
      "--disable=servicelb"
    ];
  };

  system.activationScripts.fluxBootstrap.text = ''
    if kubectl get ns flux-system >/dev/null 2>&1; then
      echo "Flux already bootstrapped"
      exit 0
    fi

    if ! gh auth status >/dev/null 2>&1; then
      echo "Flux bootstrap skipped: no GitHub auth found."
      echo "Run 'gh auth login' then rebuild."
      exit 0
    fi

    echo "Bootstrapping Flux..."
    flux bootstrap github \
      --owner=michaelbrusegard \
      --repository=nix-config \
      --branch=main \
      --path=gitops/espresso  \
      --personal
  '';
}
