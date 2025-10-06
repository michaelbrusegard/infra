{ pkgs, config, userName, pkgs-unstable, pkgs-23_05, ... }: {
  imports = [
    "${pkgs-unstable.path}/nixos/modules/services/home-automation/homebridge.nix"
  ];
  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.macchiato.ssh.ports;
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
      reflector = true;
      openFirewall = true;
      allowInterfaces = [ "end0" "wg0" ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
    cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.secrets.credentialFiles.cloudflareToken;
      domains = config.secrets.macchiato.ddns.domains;
      ipv4 = true;
      ipv6 = true;
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
                url = "http://127.0.0.1:9090";
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
        dashboards.settings.providers = [
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
    homebridge = {
      enable = true;
      openFirewall = true;
      settings = {
        bridge = {
          name = "Hjemmesentral";
          username = config.secrets.macchiato.homebridge.username;
          port = 51826;
          pin = config.secrets.macchiato.homebridge.pin;
        };
        platforms = [
          {
            name = "zigbee2mqtt";
            platform = "zigbee2mqtt";
            mqtt = {
              server = "mqtt://127.0.0.1:1883";
              base_topic = "zigbee2mqtt";
              version = 5;
            };
          }
        ];
      };
    };
    zigbee2mqtt = {
      enable = true;
      package = pkgs-23_05.zigbee2mqtt;
      settings = {
        mqtt.server = "mqtt://127.0.0.1:1883";
        frontend.enabled = true;
        availability.enabled = true;
        serial = {
          port = "/dev/serial/by-id/usb-dresden_elektronik_ingenieurtechnik_GmbH_ConBee_II_DE2690606-if00";
          adapter = "deconz";
        };
      };
    };
    mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          settings.allow_anonymous = true;
        }
      ];
    };
  };
}
