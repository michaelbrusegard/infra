_: {
  # Blocky downloads its blocklists at startup and keeps serving with empty
  # lists if that fails, so it must not race the network coming up.
  systemd.services.blocky = {
    after = ["network-online.target"];
    wants = ["network-online.target"];
  };

  services.blocky = {
    enable = true;

    settings = {
      upstreams.groups.default = [
        "https://1.1.1.1/dns-query"
        "https://dns.quad9.net/dns-query"
        "https://dns.adguard-dns.com/dns-query"
      ];

      # Without this blocky resolves its own DoH hostnames through the system
      # resolver, which points back at blocky.
      bootstrapDns = [
        {
          upstream = "https://1.1.1.1/dns-query";
          ips = ["1.1.1.1" "1.0.0.1"];
        }
      ];

      blocking = {
        denylists = {
          ads_and_trackers = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          ];
          security = [
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt"
          ];
          privacy = [
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.apple.txt"
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.tiktok.txt"
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.winoffice.txt"
          ];
        };

        # Safeway's storefront does not initialize product search when its
        # Adobe Target or cookie-consent dependencies are DNS-sinkholed.
        allowlists = {
          ads_and_trackers = [
            ''
              cdn.cookielaw.org
              safewayinc.tt.omtrdc.net
            ''
          ];
          security = [
            ''
              safewayinc.tt.omtrdc.net
            ''
          ];
        };

        clientGroupsBlock.default = [
          "ads_and_trackers"
          "security"
          "privacy"
        ];
      };

      caching = {
        minTime = "5m";
        maxTime = "30m";
      };

      ports.http = 4000;
      prometheus.enable = true;
    };
  };
}
