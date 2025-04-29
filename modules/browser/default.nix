{ config, lib, pkgs, zen-browser, nix-darwin-browsers, system, userName, isDarwin, colors, ... }:

let
  cfg = config.modules.browser;

  font-inspect = pkgs.fetchFirefoxAddon {
    name = "font-inspect";
    url = "https://addons.mozilla.org/firefox/downloads/file/4073605/font_inspect-1.1.0.xpi";
    hash = "sha256-BaNaWl0iggyymOv3wvA/svt3XZjn+MgkCtjlUkIm6Ps=";
  };

in {
  options.modules.browser.enable = lib.mkEnableOption "Browser configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      firefox = {
        enable = true;
        package = if isDarwin then
          nix-darwin-browsers.packages.${system}.zen-browser-bin
        else
          zen-browser.packages.${system}.default;
        languagePacks = [ "en-GB" ];
        policies = {
          DefaultDownloadDirectory = "$HOME/Downloads";
        };
        profiles.${userName} = {
          isDefault = true;
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
              angular-devtools
              proton-pass
              proton-vpn
              refined-github
              font-inspect
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
            "browser.tabs.warnOnClose" = false;
            "browser.ctrlTab.sortByRecentlyUsed" = true;
            "browser.urlbar.shortcuts.bookmarks" = false;
            "browser.urlbar.shortcuts.tabs" = false;
            "browser.bookmarks.showMobileBookmarks" = false;
            "browser.formfill.enable" = false;
            "browser.search.suggest.enabled" = true;
            "browser.download.useDownloadDir" = true;
            "browser.download.always_ask_before_handling_new_types" = false;
            "browser.search.separatePrivateDefault" = false;

            # Pins Proton Pass extension to the toolbar and remove the other extensions from being pinned
            "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["sponsorblocker_ajay_app-browser-action","wappalyzer_crunchlabz_com-browser-action","ublock0_raymondhill_net-browser-action","_react-devtools-browser-action","_34daeb50-c2d2-4f14-886a-7160b24d66a4_-browser-action","addon_darkreader_org-browser-action","_174b2d58-b983-4501-ab4b-07e71203cb43_-browser-action","vpn_proton_ch-browser-action","_a658a273-612e-489e-b4f1-5344e672f4f5_-browser-action"],"nav-bar":["back-button","forward-button","stop-reload-button","vertical-spacer","customizableui-special-spring1","urlbar-container","customizableui-special-spring2","unified-extensions-button","_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action","78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action"],"TabsToolbar":["tabbrowser-tabs"],"vertical-tabs":[],"PersonalToolbar":["import-button","personal-bookmarks"],"zen-sidebar-top-buttons":[],"zen-sidebar-bottom-buttons":["preferences-button","zen-workspaces-button","downloads-button"],"zen-sidebar-icons-wrapper":["zen-profile-button","zen-workspaces-button","downloads-button"]},"seen":["developer-button","wappalyzer_crunchlabz_com-browser-action","ublock0_raymondhill_net-browser-action","_react-devtools-browser-action","_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action","78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action","sponsorblocker_ajay_app-browser-action","_34daeb50-c2d2-4f14-886a-7160b24d66a4_-browser-action","addon_darkreader_org-browser-action","_174b2d58-b983-4501-ab4b-07e71203cb43_-browser-action","vpn_proton_ch-browser-action","_a658a273-612e-489e-b4f1-5344e672f4f5_-browser-action"],"dirtyAreaCache":["nav-bar","vertical-tabs","zen-sidebar-icons-wrapper","PersonalToolbar","unified-extensions-area","TabsToolbar","zen-sidebar-bottom-buttons"],"currentVersion":21,"newElementCount":4}'';

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
            "zen.welcome-screen.seen" = true;
            "zen.urlbar.behavior" = "float";
            "zen.view.compact.animate-sidebar" = false;
            "zen.view.experimental-no-window-controls" = true;
            "zen.view.show-bottom-border" = true;
            "zen.view.show-newtab-button-top" = false;
            "zen.tabs.show-newtab-vertical" = false;
            "zen.theme.color-prefs.amoled" = true;
            "zen.theme.accent-color" = 	colors.mocha.blue;
            "zen.theme.color-prefs.use-workspace-colors" = false;
            "zen.themes.updated-value-observer" = false;
            "zen.splitView.change-on-hover" = true;
            "zen.glance.enabled" = false;
            "zen.glance.activation-method" = "meta";
            "zen.workspaces.force-container-workspace" = true;
            "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;

            # Theme
            "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
            "browser.theme.content-theme" = 0;
            "browser.theme.toolbar-theme" = 0;
            "font.name.serif.x-western" = "SF Pro";

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
            default = "search";
            force = true;
            order = ["search"];
            engines = {
              "search" = {
                urls = [{
                  template = "https://duckduckgo.com/?q={searchTerms}";
                }];
                icon = "https://duckduckgo.com/favicon.ico";
                updateInterval = 24 * 60 * 60 * 1000;
                definedAliases = ["@d"];
              };
              "google".metaData.remove = true;
              "bing".metaData.remove = true;
              "amazondotcom-us".metaData.remove = true;
              "ddg".metaData.remove = true;
              "ebay".metaData.remove = true;
              "wikipedia".metaData.remove = true;
              "youtube".metaData.remove = true;
            };
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
    home = {
      file = lib.mkMerge [
        (lib.mkIf (!isDarwin) {
          ".mozilla/firefox/${userName}/zen-keyboard-shortcuts.json".source = ./config/zen-keyboard-shortcuts.json;
          ".mozilla/firefox/${userName}/zen-themes.json".source = ./config/zen-themes.json;
        })
        (lib.mkIf isDarwin {
          "Library/Application Support/Zen Browser/Profiles/default/zen-keyboard-shortcuts.json".source = ./config/zen-keyboard-shortcuts.json;
          "Library/Application Support/Zen Browser/Profiles/default/zen-themes.json".source = ./config/zen-themes.json;
        })
      ];
      activation = lib.mkIf (!isDarwin) {
        linkZenProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
          $DRY_RUN_CMD mkdir -p $HOME/.zen
          $DRY_RUN_CMD rm -rf $HOME/.zen/*
          $DRY_RUN_CMD ln -sf $HOME/.mozilla/firefox/* $HOME/.zen/
        '';
      };
    };
  };
}
