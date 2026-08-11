{
  config,
  pkgs,
  ...
}: let
  # Stream runtime kernel printk over UDP to the router after lan0 is ready.
  # Loading netconsole as a module is deliberate: the stock kernel builds it
  # modular, so a netconsole= kernel parameter is ignored.
  nodeIPs = {
    "espresso-0" = "10.0.187.2";
    "espresso-1" = "10.0.187.3";
    "espresso-2" = "10.0.187.4";
  };
  nodePorts = {
    "espresso-0" = 6666;
    "espresso-1" = 6667;
    "espresso-2" = 6668;
  };
  srcIP = nodeIPs.${config.networking.hostName};
  routerIP = "10.0.187.1";
  routerMAC = "a8:b8:e0:06:41:cc";
  target = "6666@${srcIP}/lan0,${toString nodePorts.${config.networking.hostName}}@${routerIP}/${routerMAC}";
in {
  systemd.services.netconsole-sender = {
    description = "Stream kernel messages to Macchiato";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "-${pkgs.kmod}/bin/modprobe -r netconsole";
      ExecStart = "${pkgs.kmod}/bin/modprobe netconsole netconsole=${target}";
      ExecStop = "${pkgs.kmod}/bin/modprobe -r netconsole";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
