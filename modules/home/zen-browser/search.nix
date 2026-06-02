{pkgs, ...}: let
  nixSnowflakeIcon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
in {
  programs.zen-browser.profiles."default".search = {
    force = true;
    default = "ddg";
    privateDefault = "ddg";
    order = [
      "ddg"
      "ChatGPT"
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
      "ChatGPT" = {
        urls = [
          {
            template = "https://chatgpt.com/";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://chatgpt.com/favicon.ico";
        definedAliases = ["@gpt" "@chatgpt" "@ai"];
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
        definedAliases = ["@np" "@pkgs" "@nixpkgs"];
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
        definedAliases = ["@no" "@nop" "@nixopt"];
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
        definedAliases = ["@hm" "@hmop" "@hmgr"];
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
