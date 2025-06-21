{ pkgs, config, userName, ... }: {
  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.leggero.ssh.ports;
      authorizedKeysInHomedir = false;
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
      allowInterfaces = [ "end0" ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
    cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.secrets.credentialFiles.cloudflareToken;
      domains = config.secrets.leggero.ddns.domains;
      ipv4 = true;
      ipv6 = false;
    };
    blocky = {
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
        prometheus.enable = true;
      };
    };
    prometheus = {
      enable = true;
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };
      scrapeConfigs = [
        {
          job_name = "blocky";
          static_configs = [
            {
              targets = [ "127.0.0.1:4000" ];
            }
          ];
        }
      ];
    };
    grafana = {
      enable = true;
      settings = {
        server.http_addr = "0.0.0.0";
        security = {
          admin_email = "";
          admin_user = userName;
          admin_password = userName;
        };
        users.default_language = "en-GB";
      };
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
        dashboards = {
          settings.providers = [
            {
              name = "default";
              orgId = 1;
              folder = "Blocky";
              type = "file";
              disableDeletion = false;
              editable = true;
              options = {
                path = pkgs.fetchurl {
                  url = "https://0xerr0r.github.io/blocky/latest/blocky-grafana.json";
                  hash = "sha256-InIKXAmovhDfYqBFGDNk/Cyj0hQQVjTuyDdTumV2yOg=";
                };
              };
            }
          ];
        };
      };
    };
    home-assistant = {
      enable = true;
      openFirewall = true;
      extraComponents = [
        "backup"
        "bluetooth"
        "config"
        "dhcp"
        "energy"
        "history"
        "homeassistant_alerts"
        "logbook"
        "mobile_app"
        "my"
        "ssdp"
        "sun"
        "usb"
        "zeroconf"
        "zha"
        "met"
      ];
      config = {
        homeassistant = {
          name = config.secrets.leggero.homeAssistant.name;
          latitude = config.secrets.leggero.homeAssistant.latitude;
          longitude = config.secrets.leggero.homeAssistant.longitude;
          time_zone = "Europe/Oslo";
          unit_system = "metric";
          temperature_unit = "C";
        };
      };
    };
  };
}
