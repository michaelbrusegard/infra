{ ... }: {
  boot.kernel = {
    sysctl."net.ipv4.ip_forward" = true;
    sysctl."net.ipv6.conf.all.forwarding" = true;
  };
}
