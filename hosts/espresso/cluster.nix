{
  pkgs,
  config,
  lib,
  ...
}: let
  nodeIPs = {
    "espresso-0" = "10.0.186.18";
    "espresso-1" = "10.0.186.19";
    "espresso-2" = "10.0.186.20";
  };
  nodeIP = nodeIPs.${config.networking.hostName};
in {
  services.k3s = {
    inherit nodeIP;
    inherit (config.secrets.k3s) tokenFile;
    clusterInit = config.networking.hostName == "espresso-0";
    serverAddr =
      lib.mkIf
      (config.networking.hostName != "espresso-0")
      "https://${nodeIPs."espresso-0"}:6443";
  };

  environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

  systemd.services.flux-bootstrap =
    lib.mkIf
    (config.networking.hostName == "espresso-0")
    {
      after = ["k3s.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.secrets.k3s.flux.envFile;
      };
      script = ''
        set -euo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        echo "Waiting for Kubernetes API..."
        until ${pkgs.kubectl}/bin/kubectl get nodes >/dev/null 2>&1; do
          sleep 2
        done
        if ${pkgs.kubectl}/bin/kubectl get ns flux-system >/dev/null 2>&1; then
          echo "Flux already bootstrapped"
          exit 0
        fi
        echo "Bootstrapping Flux..."
        ${pkgs.fluxcd}/bin/flux bootstrap github \
          --owner=michaelbrusegard \
          --repository=nix-config \
          --branch=main \
          --path=gitops/espresso \
          --author-name="Flux (espresso)" \
          --personal
      '';
    };

  # Disable btrfs copy on write for main drive directories used by k3s
  systemd.tmpfiles.rules = [
    "d /var/lib/longhorn 0755 root root - -"
    "h /var/lib/longhorn - - - - +C"
    "d /var/lib/rancher/k3s 0755 root root - -"
    "h /var/lib/rancher/k3s - - - - +C"
  ];
}
