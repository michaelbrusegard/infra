{ config, lib, pkgs, zen-browser, system, username, nur, isDarwin, ... }:

let
  cfg = config.modules.browser;
in {
  options.modules.browser.enable = lib.mkEnableOption "Browser configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      firefox = {
        enable = true;
        package = if isDarwin then
          pkgs.runCommand "zen-browser-wrapper" {} ''
            mkdir -p $out/bin
            ln -s "/Applications/Zen Browser.app/Contents/MacOS/zen" $out/bin/firefox
          ''
        else
          zen-browser.packages.${system}.default;
        languagePacks = [ "en-GB" ];
        policies = {
          DefaultDownloadDirectory = "$HOME/Downloads";
        };
        profiles.${username} = {
          containers = {
            personal = {
              color = "red";
              icon = "fingerprint";
              id = 0;
            };
            development = {
              color = "blue";
              icon = "chill";
              id = 1;
            };
            work = {
              color = "orange";
              icon = "briefcase";
              id = 2;
            };
          };
          containersForce = true;
          extensions = {
            force = true;
            packages = with pkgs.nur.repos.rycee.firefox-addons; [
              ublock-origin
              sponsorblock
              youtube-shorts-block
              wappalyzer
              react-devtools
              proton-pass
              proton-vpn
            ];
          };
          settings = {
            # Firefox behavior
            "browser.aboutConfig.showWarning" = false;
            "browser.shell.checkDefaultBrowser" = false;
            "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
            "browser.newtabpage.enabled" = false;
            "browser.tabs.loadInBackground" = false;
            "browser.tabs.loadBookmarksInTabs" = true;
            "browser.ctrlTab.sortByRecentlyUsed" = true;
            "browser.urlbar.shortcuts.bookmarks" = false;
            "browser.urlbar.shortcuts.tabs" = false;
            "browser.bookmarks.showMobileBookmarks" = false;
            "browser.formfill.enable" = true;
            "browser.search.suggest.enabled" = true;

            # Keybinds
            "ui.key.accelKey" = 224;

            # Privacy
            "privacy.donottrackheader.enabled" = true;
            "privacy.history.custom" = true;
            "privacy.clearOnShutdown_v2.formdata" = true;
            "signon.rememberSignons" = false;
            "dom.security.https_only_mode_ever_enabled" = true;
            "network.dns.disablePrefetch" = true;
            "network.prefetch-next" = false;
            "network.predictor.enabled" = false;
            "network.http.speculative-parallel-limit" = 0;

            # Devtools
            "devtools.cache.disabled" = true;

            # Zen-specific settings
            "zen.urlbar.behavior" = "float";
            "zen.view.compact.animate-sidebar" = false;
            "zen.view.experimental-no-window-controls" = true;
            "zen.view.show-bottom-border" = true;
            "zen.view.show-newtab-button-top" = false;
            "zen.tabs.show-newtab-vertical" = false;
            "zen.theme.color-prefs.amoled" = true;
            "zen.splitView.change-on-hover" = true;
            "zen.glance.enabled" = false;
            "zen.glance.activation-method" = "meta";
            "zen.workspaces.force-container-workspace" = true;
            "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;
            "zen.sidebar.data" = "{\"data\":{\"p4\":{\"url\":\"https://translate.google.com/\",\"ua\":true},\"p1738933158209\":{\"url\":\"https://t3.chat/\",\"ua\":true}},\"index\":[\"p1738933158209\",\"p4\"]}";

            # Theme
            "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
            "browser.theme.content-theme" = 0;
            "browser.theme.toolbar-theme" = 0;

            # Language
            "intl.accept_languages" = "en,no";
            "intl.locale.requested" = "en-GB";
            "browser.ml.chat.shortcuts" = false;

            # Extensions
            "extensions.autoDisableScopes" = 0;

            "uBlock0@raymondhill.net".settings = {
              selectedFilterLists = [
                "ublock-filters"
                "ublock-badware"
                "ublock-privacy"
                "ublock-unbreak"
                "ublock-quick-fixes"
                "fanboy-cookiemonster"
                "easylist-cookie"
                "adguard-cookies"
                "adguard-popup"
                "adguard-mobile"
                "block-annoyances"
                "adguard-social"
              ];
            };
          };
          search = {
            default = "Search";
            force = true;
            order = ["Search"];
            engines = {
              "Search" = {
                urls = [{
                  template = "https://duckduckgo.com/?q={searchTerms}";
                }];
                iconUpdateURL = "https://duckduckgo.com/favicon.ico";
                updateInterval = 24 * 60 * 60 * 1000;
                definedAliases = ["@d"];
              };
              "Google".metaData.hidden = true;
              "Bing".metaData.hidden = true;
              "Amazon.com".metaData.hidden = true;
              "DuckDuckGo".metaData.hidden = true;
              "eBay".metaData.hidden = true;
              "Wikipedia".metaData.hidden = true;
              "YouTube".metaData.hidden = true;
            };
            disableSearchEngineDetection = true;
          };
          userChrome = ''
            :root {
              --attention-dot-color: rgba(0, 0, 0, 0) !important;
            }
          '';
        };
      };
      chromium.enable = true;
    };
  };
}
