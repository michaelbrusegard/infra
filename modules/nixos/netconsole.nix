{config, ...}: let
  # Stream kernel printk over UDP to the router (macchiato) from early boot, so
  # a wedge that goes dark before journald (early panic, LUKS stall) is still
  # captured. Raw UDP sender with no ARP, so the gateway MAC is hardcoded.
  nodeIPs = {
    "espresso-0" = "10.0.187.2";
    "espresso-1" = "10.0.187.3";
    "espresso-2" = "10.0.187.4";
  };
  srcIP = nodeIPs.${config.networking.hostName};
  routerIP = "10.0.187.1";
  routerMAC = "a8:b8:e0:06:41:cc";
in {
  boot.kernelParams = [
    "netconsole=6666@${srcIP}/lan0,6666@${routerIP}/${routerMAC}"
  ];
}
