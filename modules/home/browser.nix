{
  pkgs,
  lib,
  isWsl,
  inputs,
  ...
}: {
  imports = [
    inputs.zen-browser.homeModules.beta
  ];

  config = lib.mkIf (!isWsl) {
    programs.zen-browser = {
      enable = true;
      darwinDefaultsId = "app.zen-browser.zen";
      languagePacks = ["en-GB"];
      policies = {
        AutofillAddressEnabled = true;
        AutofillCreditCardEnabled = false;
        DisableAppUpdate = true;
        DisableFeedbackCommands = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;

        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };

        SanitizeOnShutdown = {
          FormData = true;
          Cache = true;
        };

        ExtensionSettings = {
          # uBlock Origin - ad blocker
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };
          # SponsorBlock - skip YouTube sponsors
          "sponsorBlocker@ajay.app" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
            installation_mode = "force_installed";
          };
          # YouTube Shorts Block
          "{34daeb50-c2d2-4f14-886a-7160b24d66a4}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-shorts-block/latest.xpi";
            installation_mode = "force_installed";
          };
          # Wappalyzer - technology profiler
          "wappalyzer@crunchlabz.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/wappalyzer/latest.xpi";
            installation_mode = "force_installed";
          };
          # React DevTools
          "@react-devtools" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/react-devtools/latest.xpi";
            installation_mode = "force_installed";
          };
          # Proton Pass - password manager (PINNED to navbar)
          "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi";
            installation_mode = "force_installed";
            default_area = "navbar";
          };
          # Proton VPN
          "vpn@proton.ch" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/proton-vpn-firefox-extension/latest.xpi";
            installation_mode = "force_installed";
          };
          # Refined GitHub
          "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/refined-github-/latest.xpi";
            installation_mode = "force_installed";
          };
          # Fonts Ninja
          "{cade9e47-97ad-4d85-b8a7-002c1f4e8f04}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/fonts-ninja/latest.xpi";
            installation_mode = "force_installed";
          };
          # GitHub Repository Size
          "github-repository-size@pranavmangal" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/gh-repo-size/latest.xpi";
            installation_mode = "force_installed";
          };
          # GitHub No More
          "github-no-more@ihatereality.space" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/github-no-more/latest.xpi";
            installation_mode = "force_installed";
          };
          # ClearURLs - remove tracking from URLs
          "{74145f27-f039-47ce-a470-a662b129930a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi";
            installation_mode = "force_installed";
          };
          # Return YouTube Dislikes
          "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/return-youtube-dislikes/latest.xpi";
            installation_mode = "force_installed";
          };
          # Catppuccin Web File Icons
          "{bbb880ce-43c9-47ae-b746-c3e0096c5b76}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/catppuccin-web-file-icons/latest.xpi";
            installation_mode = "force_installed";
          };
          # Steam Database
          "firefox-extension@steamdb.info" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/steam-database/latest.xpi";
            installation_mode = "force_installed";
          };
          # Search Engine Ad Remover
          "@searchengineadremover" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/searchengineadremover/latest.xpi";
            installation_mode = "force_installed";
          };
          # Decentraleyes - local CDN emulation
          "jid1-BoFifL9Vbdl2zQ@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/decentraleyes/latest.xpi";
            installation_mode = "force_installed";
          };
          # TrackMeNot - search privacy
          "trackmenot@mrl.nyu.edu" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/trackmenot/latest.xpi";
            installation_mode = "force_installed";
          };
          # Custom User Agent Revived
          "{861a3982-bb3b-49c6-bc17-4f50de104da1}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/custom-user-agent-revived/latest.xpi";
            installation_mode = "force_installed";
          };
          # Chameleon - fingerprint protection
          "{3579f63b-d8ee-424f-bbb6-6d0ce3285e6a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/chameleon-ext/latest.xpi";
            installation_mode = "force_installed";
          };
          # Bitwarden - password manager
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            installation_mode = "force_installed";
          };
          # Solid DevTools
          "{abfd162e-9948-403a-a75c-6e61184e1d47}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/solid-devtools/latest.xpi";
            installation_mode = "force_installed";
          };
          # Google Lighthouse
          "{cf3dba12-a848-4f68-8e2d-f9fadc0721de}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/google-lighthouse/latest.xpi";
            installation_mode = "force_installed";
          };
        };

        Preferences = {
          # UI/UX Preferences
          "browser.aboutConfig.showWarning" = {
            Value = false;
            Status = "locked";
          };
          "browser.tabs.warnOnClose" = {
            Value = false;
            Status = "locked";
          };
          "media.videocontrols.picture-in-picture.video-toggle.enabled" = {
            Value = true;
            Status = "locked";
          };
          "browser.gesture.swipe.left" = {
            Value = "";
            Status = "locked";
          };
          "browser.gesture.swipe.right" = {
            Value = "";
            Status = "locked";
          };
          "browser.tabs.hoverPreview.enabled" = {
            Value = true;
            Status = "locked";
          };
          "browser.newtabpage.activity-stream.feeds.topsites" = {
            Value = false;
            Status = "locked";
          };
          "browser.topsites.contile.enabled" = {
            Value = false;
            Status = "locked";
          };

          # Performance
          "gfx.webrender.all" = {
            Value = true;
            Status = "locked";
          };
          "network.http.http3.enabled" = {
            Value = true;
            Status = "locked";
          };
          "network.socket.ip_addr_any.disabled" = {
            Value = true;
            Status = "locked";
          };

          # Security - Force HTTPS only mode
          "dom.security.https_only_mode" = {
            Value = true;
            Status = "locked";
          };

          # Content blocking - strict tracking protection
          "browser.contentblocking.category" = {
            Value = "strict";
            Status = "locked";
          };

          # Enable middle-click autoscroll
          "general.autoScroll" = {
            Value = true;
            Status = "locked";
          };

          # Enable find-as-you-type (press / to search)
          "accessibility.typeaheadfind" = {
            Value = true;
            Status = "locked";
          };

          # Firefox Behavior
          "browser.shell.checkDefaultBrowser" = {
            Value = false;
            Status = "locked";
          };
          "browser.startup.homepage" = {
            Value = "chrome://browser/content/blanktab.html";
            Status = "locked";
          };
          "browser.newtabpage.enabled" = {
            Value = false;
            Status = "locked";
          };
          "browser.tabs.loadBookmarksInTabs" = {
            Value = true;
            Status = "locked";
          };
          "browser.ctrlTab.sortByRecentlyUsed" = {
            Value = true;
            Status = "locked";
          };
          "browser.urlbar.shortcuts.bookmarks" = {
            Value = false;
            Status = "locked";
          };
          "browser.urlbar.shortcuts.tabs" = {
            Value = false;
            Status = "locked";
          };
          "browser.bookmarks.showMobileBookmarks" = {
            Value = false;
            Status = "locked";
          };
          "browser.formfill.enable" = {
            Value = false;
            Status = "locked";
          };
          "browser.search.suggest.enabled" = {
            Value = false;
            Status = "locked";
          };
          "browser.download.useDownloadDir" = {
            Value = true;
            Status = "locked";
          };
          "browser.download.always_ask_before_handling_new_types" = {
            Value = false;
            Status = "locked";
          };
          "browser.search.separatePrivateDefault" = {
            Value = false;
            Status = "locked";
          };

          # Privacy
          "privacy.donottrackheader.enabled" = {
            Value = true;
            Status = "locked";
          };
          "privacy.clearOnShutdown_v2.formdata" = {
            Value = true;
            Status = "locked";
          };
          "signon.rememberSignons" = {
            Value = false;
            Status = "locked";
          };
          "dom.security.https_only_mode_ever_enabled" = {
            Value = true;
            Status = "locked";
          };
          "network.dns.disablePrefetch" = {
            Value = true;
            Status = "locked";
          };
          "network.prefetch-next" = {
            Value = false;
            Status = "locked";
          };
          "network.predictor.enabled" = {
            Value = false;
            Status = "locked";
          };
          "network.http.speculative-parallel-limit" = {
            Value = 0;
            Status = "locked";
          };

          # Devtools
          "devtools.cache.disabled" = {
            Value = true;
            Status = "locked";
          };

          # Extensions
          "extensions.autoDisableScopes" = {
            Value = 0;
            Status = "locked";
          };

          # Locale settings
          "intl.accept_languages" = {
            Value = "en,no";
            Status = "locked";
          };
          "intl.locale.requested" = {
            Value = "en-GB";
            Status = "locked";
          };
        };

        # Extension-specific settings
        "3rdparty" = {
          Extensions = {
            "uBlock0@raymondhill.net" = {
              settings = {
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
                  "adguard-spyware"
                  "block-annoyances"
                  "adguard-social"
                ];
              };
            };
          };
        };
      };

      profiles.default = {
        isDefault = true;
        settings = {
          # Zen Browser UI/Workflow Settings
          "zen.workspaces.continue-where-left-off" = true;
          "zen.workspaces.natural-scroll" = true;
          "zen.view.compact.hide-tabbar" = true;
          "zen.view.compact.hide-toolbar" = true;
          "zen.view.compact.animate-sidebar" = false;
          "zen.welcome-screen.seen" = true;
          "zen.urlbar.behavior" = "float";
          "zen.view.experimental-no-window-controls" = true;
          "zen.view.show-bottom-border" = true;
          "zen.view.show-newtab-button-top" = false;
          "zen.tabs.show-newtab-vertical" = false;
          "zen.theme.color-prefs.amoled" = true;
          "zen.theme.color-prefs.use-workspace-colors" = true;
          "zen.themes.updated-value-observer" = false;
          "zen.splitView.change-on-hover" = true;
          "zen.glance.enabled" = false;
          "zen.glance.activation-method" = "meta";
          "zen.workspaces.force-container-workspace" = true;
          "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;
          "zen.theme.accent-color" = "#89b4fa";

          # Font settings
          "font.name.serif.x-western" = "Roboto";
          "font.name.sans-serif.x-western" = "Roboto";
          "font.name.monospace.x-western" = "Roboto Mono";
        };
        userChrome = ''
          :root {
            --attention-dot-color: rgba(0, 0, 0, 0) !important;
          }

          #zen-current-workspace-indicator-container {
            display: none;
          }
        '';
        mods = [
          "253a3a74-0cc4-47b7-8b82-996a64f030d5" # Floating History
          "4ab93b88-151c-451b-a1b7-a1e0e28fa7f8" # No Sidebar Scrollbar
          "7190e4e9-bead-4b40-8f57-95d852ddc941" # Tab title fixes
          "803c7895-b39b-458e-84f8-a521f4d7a064" # Hide Inactive Workspaces
          "b51ff956-6aea-47ab-80c7-d6c047c0d510" # Disable Status Bar
          "a6335949-4465-4b71-926c-4a52d34bc9c0" # Better Find Bar
          "c6813222-6571-4ba6-8faf-58f3343324f6" # Disable Rounded Corners
          "c8d9e6e6-e702-4e15-8972-3596e57cf398" # Zen Back Forward
          "cb15abdb-0514-4e09-8ce5-722cf1f4a20f" # Hide Extension Name
          "d8b79d4a-6cba-4495-9ff6-d6d30b0e94fe" # Better Active Tab
          "e122b5d9-d385-4bf8-9971-e137809097d0" # No Top Sites
          "f7c71d9a-bce2-420f-ae44-a64bd92975ab" # Better Unloaded Tabs
          "fd24f832-a2e6-4ce9-8b19-7aa888eb7f8e" # Quietify
          "22c9ec3b-7c62-46ae-991f-c8fff5046829" # Tab Numbers
          "4c2bec61-7f6c-4e5c-bdc6-c9ad1aba1827" # Vertical Split Tab Groups
          "4596d8f9-f0b7-4aeb-aa92-851222dc1888" # Only Close On Hover
          "ae051a40-3e3a-429a-a6f4-199a28b18a75" # Only Reset On Hover
          "599a1599-e6ab-4749-ab22-de533860de2c" # Pimp your PiP
        ];
      };
    };

    programs.chromium = {
      enable = true;
      package = pkgs.brave;
    };
  };
}
