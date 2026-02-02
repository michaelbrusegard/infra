{pkgs, ...}: let
  nixSnowflakeIcon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
in {
  programs.zen-browser.profiles."default".search = {
    force = true;
    default = "ddg";
    privateDefault = "ddg";
    order = [
      "ddg"
      "T3 Chat"
      "Nix Packages"
      "Nix Options"
      "Home Manager"
      "Maps"
      "MakerWorld"
      "Printables"
    ];
    engines = {
      "ddg" = {
        urls = [
          {
            template = "https://duckduckgo.com";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
              {
                name = "origin";
                value = "unknown";
              }
            ];
          }
        ];
        icon = "https://duckduckgo.com/favicon.ico";
        definedAliases = ["@dd" "@ddg" "@duck"];
      };
      "T3 Chat" = {
        urls = [
          {
            template = "https://www.t3.chat/new";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://t3.chat/favicon.ico";
        definedAliases = ["@t3" "@t3chat"];
      };
      "Nix Packages" = {
        urls = [
          {
            template = "https://search.nixos.org/packages";
            params = [
              {
                name = "type";
                value = "packages";
              }
              {
                name = "channel";
                value = "unstable";
              }
              {
                name = "query";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = nixSnowflakeIcon;
        definedAliases = ["@pkgs"];
      };
      "Nix Options" = {
        urls = [
          {
            template = "https://search.nixos.org/options";
            params = [
              {
                name = "channel";
                value = "unstable";
              }
              {
                name = "query";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = nixSnowflakeIcon;
        definedAliases = ["@nop"];
      };
      "Home Manager" = {
        urls = [
          {
            template = "https://home-manager-options.extranix.com/";
            params = [
              {
                name = "query";
                value = "{searchTerms}";
              }
              {
                name = "release";
                value = "master"; # unstable
              }
            ];
          }
        ];
        icon = nixSnowflakeIcon;
        definedAliases = ["@hmop"];
      };
      "Maps" = {
        urls = [
          {
            template = "http://maps.apple.com";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://maps.apple.com/favicon.ico";
        definedAliases = ["@maps"];
      };
      "MakerWorld" = {
        urls = [
          {
            template = "https://makerworld.com/en/search/models";
            params = [
              {
                name = "keyword";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://makerworld.com/favicon.ico";
        definedAliases = ["@mw" "@maker"];
      };
      "Printables" = {
        urls = [
          {
            template = "https://www.printables.com/search/models";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://www.printables.com/favicon.ico";
        definedAliases = ["@pt" "@print" "@printables"];
      };
      "bing".metaData.hidden = true;
      "google".metaData.hidden = true;
      "perplexity".metaData.hidden = true;
      "wikipedia".metaData.hidden = true;
    };
  };
}
