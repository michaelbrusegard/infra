{...}: {
  services.blocky = {
    enable = true;

    settings = {
      upstreams.groups.default = [
        "https://1.1.1.1/dns-query"
        "https://dns.quad9.net/dns-query"
        "https://dns.adguard-dns.com/dns-query"
      ];

      blocking = {
        denylists = {
          ads_and_trackers = [
            "https://oisd.nl/abp"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          ];
          security = [
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt"
          ];
          privacy = [
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/native.apple.txt"
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/native.tiktok.txt"
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/native.windows.txt"
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
    };
  };
}
