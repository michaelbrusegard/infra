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
    envoyConfig.enabled = true;
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
  systemd.services = {
    cilium-bootstrap =
      lib.mkIf
      (config.networking.hostName == "espresso-0")
      {
        description = "Bootstrap Cilium CNI for k3s";
        after = ["k3s.service"];
        before = ["flux-bootstrap.service"];
        requires = ["k3s.service"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
          until ${lib.getExe pkgs.kubectl} get nodes >/dev/null 2>&1; do
            sleep 2
          done
          if ${lib.getExe pkgs.kubectl} get daemonset cilium -n kube-system >/dev/null 2>&1; then
            echo "Cilium already installed, skipping bootstrap"
            exit 0
          fi
          echo "Installing Cilium CNI..."
          ${lib.getExe pkgs.kubernetes-helm} install cilium cilium \
            --repo https://helm.cilium.io/ \
            --namespace kube-system \
            -f ${ciliumBootstrapValues}
          echo "Waiting for Cilium to be ready..."
          ${lib.getExe pkgs.kubectl} -n kube-system rollout status daemonset/cilium --timeout=300s
        '';
      };

    flux-bootstrap =
      lib.mkIf
      (config.networking.hostName == "espresso-0")
      {
        before = [
          "flux-sops-age-key.service"
          "flux-nix-secrets-auth.service"
        ];
        after = ["k3s.service" "cilium-bootstrap.service"];
        requires = ["k3s.service" "cilium-bootstrap.service"];
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
          until ${lib.getExe pkgs.kubectl} get nodes >/dev/null 2>&1; do
            sleep 2
          done
          if ${lib.getExe pkgs.kubectl} get ns flux-system >/dev/null 2>&1; then
            echo "Flux already bootstrapped"
            exit 0
          fi
          echo "Bootstrapping Flux..."
          ${lib.getExe pkgs.fluxcd} bootstrap github \
            --owner=michaelbrusegard \
            --repository=nix-config \
            --branch=main \
            --path=gitops/espresso \
            --author-name="Flux (espresso)" \
            --personal
        '';
      };

    flux-sops-age-key =
      lib.mkIf
      (config.networking.hostName == "espresso-0")
      {
        after = ["k3s.service" "flux-bootstrap.service"];
        requires = ["k3s.service" "flux-bootstrap.service"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
          test -f ${config.secrets.k3s.flux.sopsAgeKeyFile}
          until ${lib.getExe pkgs.kubectl} get ns flux-system >/dev/null 2>&1; do
            sleep 2
          done
          ${lib.getExe pkgs.kubectl} -n flux-system create secret generic sops-age \
            --from-file=age.agekey=${config.secrets.k3s.flux.sopsAgeKeyFile} \
            --dry-run=client -o yaml | ${lib.getExe pkgs.kubectl} apply -f -
        '';
      };

    flux-nix-secrets-auth =
      lib.mkIf
      (config.networking.hostName == "espresso-0")
      {
        after = ["k3s.service" "flux-bootstrap.service"];
        requires = ["k3s.service" "flux-bootstrap.service"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
          test -f ${config.secrets.k3s.flux.nixSecretsDeployKeyFile}
          until ${lib.getExe pkgs.kubectl} get ns flux-system >/dev/null 2>&1; do
            sleep 2
          done
          ${lib.getExe pkgs.kubectl} -n flux-system create secret generic nix-secrets-auth \
            --from-file=identity=${config.secrets.k3s.flux.nixSecretsDeployKeyFile} \
            --from-file=known_hosts=${pkgs.writeText "github-known-hosts" ''
            github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
            github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
          ''} \
            --dry-run=client -o yaml | ${lib.getExe pkgs.kubectl} apply -f -
        '';
      };
  };
}
