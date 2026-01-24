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
    enable = true;
    clusterInit = config.networking.hostName == "espresso-0";
    serverAddr =
      lib.mkIf
      (config.networking.hostName != "espresso-0")
      "https://${nodeIPs."espresso-0"}:6443";
    gracefulNodeShutdown.enable = true;
    inherit (config.secrets.services.k3s) tokenFile;
    extraFlags = [
      "--node-ip=${nodeIP}"
      "--advertise-address=${nodeIP}"
      "--write-kubeconfig-mode=0644"
      "--disable=traefik"
      "--disable=servicelb"
    ];
  };

  environment = {
    etc."kubeconfig".source = "/etc/rancher/k3s/k3s.yaml";
    sessionVariables.KUBECONFIG = "/etc/kubeconfig";
  };

  systemd.services.flux-bootstrap =
    lib.mkIf
    (config.networking.hostName == "espresso-0")
    {
      after = ["k3s.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        echo "Waiting for Kubernetes API..."
        ${pkgs.kubectl}/bin/kubectl wait \
          --for=condition=Ready nodes --all \
          --timeout=180s

        if ${pkgs.kubectl}/bin/kubectl get ns flux-system >/dev/null 2>&1; then
          echo "Flux already bootstrapped"
          exit 0
        fi

        if ! ${pkgs.gh}/bin/gh auth status >/dev/null 2>&1; then
          echo "Flux bootstrap skipped: no GitHub auth found."
          echo "Run 'gh auth login' then rebuild."
          exit 0
        fi

        echo "Bootstrapping Flux..."
        ${pkgs.fluxcd}/bin/flux bootstrap github \
          --owner=michaelbrusegard \
          --repository=nix-config \
          --branch=main \
          --path=gitops/espresso \
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
