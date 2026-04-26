_: {
  nixpkgs.config.permittedInsecurePackages = [
    "unifi-controller-9.5.21"
  ];
  services.unifi.enable = true;

  # HTTP reverse proxy so the k8s internal gateway can reach Unifi's HTTPS UI
  services.caddy = {
    enable = true;
    virtualHosts."http://0.0.0.0:8444" = {
      extraConfig = ''
        reverse_proxy https://127.0.0.1:8443 {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    };
  };
}
