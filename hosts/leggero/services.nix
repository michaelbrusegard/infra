{ config, ... }: {
  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.leggero.sshPorts;
      authorizedKeysInHomedir = false;
      authorizedKeysFiles = config.secrets.leggero.authorizedKeysFiles;
      hostKeys = [];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    fail2ban = {
      enable = true;
      bantime = "1h";
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      allowInterfaces = [ "eth0" ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
    cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.secrets.credentialFiles.cloudflareToken;
      domains = config.secrets.leggero.ddnsDomains;
      ipv4 = true;
      ipv6 = false;
    };
    blocky = {
      enable = true;
      settings = {
        upstreams.groups.default = [
          "https://dns.quad9.net/dns-query"
          "https://dns.adguard-dns.com/dns-query"
          "https://1.1.1.1/dns-query"
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
        clientLookup = {
          upstream = "10.10.61.1";
        };
        caching = {
          minTime = "5m";
          maxTime = "30m";
        };
        prometheus.enable = true;
      };
    };
    prometheus = {
      enable = true;
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };
      scrapeConfigs = {
        blocky = {
          static_configs = [
            {
              targets = [ "localhost:4000" ];
            }
          ];
        };
      };
    };
    grafana = {
      enable = true;
      provision = {
        enable = true;
        datasources = {
          settings = {
            apiVersion = 1;
            deleteDatasources = [
              {
                name = "Prometheus";
                orgId = 1;
              }
            ];
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                access = "proxy";
                orgId = 1;
                url = "http://localhost:9090";
                isDefault = true;
                jsonData = {
                  graphiteVersion = "1.1";
                  tlsAuth = false;
                  tlsAuthWithCACert = false;
                };
                version = 1;
                editable = true;
              }
            ];
          };
        };
      };
    };
    home-assistant = {
      enable = true;
      openFirewall = true;
    };
  };
}
