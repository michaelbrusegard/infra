{lib, pkgs, ...}: {
  nixpkgs.config.permittedInsecurePackages = [
    "unifi-controller-9.5.21"
  ];
  services.unifi.enable = true;

  # Plain TCP to TLS bridge so the k8s internal gateway can reach Unifi's HTTPS UI
  systemd.services.unifi-proxy = {
    after = ["network.target" "unifi.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.socat} TCP-LISTEN:8444,fork,reuseaddr OPENSSL:127.0.0.1:8443,verify=0";
      Restart = "always";
    };
  };
}
