{
  pkgs,
  config,
  lib,
  ...
}: let
  nodeIPs = {
    "espresso-0" = "10.0.187.2";
    "espresso-1" = "10.0.187.3";
    "espresso-2" = "10.0.187.4";
  };
  nodeIPv6s = {
    "espresso-0" = "fd7a:115c:a1e0:187::2";
    "espresso-1" = "fd7a:115c:a1e0:187::3";
    "espresso-2" = "fd7a:115c:a1e0:187::4";
  };
  nodeIP = "${nodeIPs.${config.networking.hostName}},${nodeIPv6s.${config.networking.hostName}}";

  # Bootstrap Cilium values — a subset of the Flux HelmRelease values, without
  # gatewayAPI (CRDs don't exist yet). Flux upgrades the release with the full
  # config once running.
  ciliumBootstrapValues = pkgs.writeText "cilium-bootstrap-values.json" (builtins.toJSON {
    ipv4.enabled = true;
    ipv6.enabled = true;
    ipam.mode = "kubernetes";
    k8sServiceHost = nodeIPs."espresso-0";
    k8sServicePort = 6443;
    kubeProxyReplacement = true;
    routingMode = "native";
    autoDirectNodeRoutes = true;
    ipv4NativeRoutingCIDR = "10.42.0.0/16";
    ipv6NativeRoutingCIDR = "fd42::/56";
    bandwidthManager = {
      enabled = true;
      bbr = true;
    };
    bpf = {
      masquerade = true;
      hostRouting = true;
    };
    hostFirewall.enabled = true;
    bgpControlPlane.enabled = true;
    externalIPs.enabled = true;
    hubble = {
      relay.enabled = true;
      ui.enabled = true;
    };
  });
in {
  services.k3s = {
    inherit nodeIP;
    inherit (config.secrets.k3s) tokenFile;
    clusterInit = config.networking.hostName == "espresso-0";
    serverAddr =
      lib.mkIf
      (config.networking.hostName != "espresso-0")
      "https://${nodeIPs."espresso-0"}:6443";
    extraFlags = [
      "--cluster-cidr=10.42.0.0/16,fd42::/56"
      "--service-cidr=10.43.0.0/16,fd43::/112"
    ];
  };

  # One-time Cilium bootstrap to break the chicken-and-egg: nodes need CNI to
  # be Ready, Flux needs Ready nodes to schedule, Cilium is deployed by Flux.
  # After this runs once, Flux adopts the Helm release and manages it.
  systemd.services.cilium-bootstrap =
    lib.mkIf
    (config.networking.hostName == "espresso-0")
    {
      description = "Bootstrap Cilium CNI for k3s";
      after = ["k3s.service"];
      before = ["flux-bootstrap.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        until ${pkgs.kubectl}/bin/kubectl get nodes >/dev/null 2>&1; do
          sleep 2
        done
        if ${pkgs.kubectl}/bin/kubectl get daemonset cilium -n kube-system >/dev/null 2>&1; then
          echo "Cilium already installed, skipping bootstrap"
          exit 0
        fi
        echo "Installing Cilium CNI..."
        ${pkgs.kubernetes-helm}/bin/helm install cilium cilium \
          --repo https://helm.cilium.io/ \
          --namespace kube-system \
          -f ${ciliumBootstrapValues}
        echo "Waiting for Cilium to be ready..."
        ${pkgs.kubectl}/bin/kubectl -n kube-system rollout status daemonset/cilium --timeout=300s
      '';
    };

  systemd.services.flux-bootstrap =
    lib.mkIf
    (config.networking.hostName == "espresso-0")
    {
      after = ["k3s.service" "cilium-bootstrap.service"];
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
}
