{
  avahi = import ./avahi.nix;
  blocky = import ./blocky;
  blocky-prometheus = import ./blocky/prometheus.nix;
  boot = import ./boot.nix;
  caddy = import ./caddy.nix;
  catppuccin = import ./catppuccin.nix;
  cloudflare-dyndns = import ./cloudflare-dyndns.nix;
  disable-documentation = import ./disable-documentation.nix;
  grafana = import ./grafana;
  grafana-blocky = import ./grafana/dashboards/blocky.nix;
  homebridge = import ./homebridge.nix;
  home-manager = import ./home-manager.nix;
  home-assistant = import ./home-assistant.nix;
  locale = import ./locale.nix;
  networking = import ./networking.nix;
  nix = import ./nix.nix;
  openssh = import ./openssh.nix;
  openthread-border-router = import ./openthread-border-router.nix;
  prometheus = import ./prometheus.nix;
  secrets = import ./secrets.nix;
  security = import ./security.nix;
  virtualisation = import ./virtualisation.nix;
}
