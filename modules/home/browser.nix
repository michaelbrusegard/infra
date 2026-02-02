{
  pkgs,
  lib,
  isWsl,
  inputs,
  ...
}: let
  nixSnowflakeIcon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
in {
  imports = [
    inputs.zen-browser.homeModules.beta
  ];

  config = lib.mkIf (!isWsl) {
    programs.zen-browser = {
      enable = true;
      darwinDefaultsId = "app.zen-browser.zen";
      languagePacks = ["en-GB"];
      policies = {
        AutofillAddressEnabled = false;
        AutofillCreditCardEnabled = false;
        DisableAppUpdate = true;
        DisableFeedbackCommands = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;

        SearchEngines = {
          Default = "DuckDuckGo";
          PreventInstalls = true;
          Remove = [
            "Google"
            "Bing"
            "eBay"
            "Wikipedia"
            "Perplexity"
          ];
        };

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
            default_area = "menupanel";
          };
          # SponsorBlock - skip YouTube sponsors
          "sponsorBlocker@ajay.app" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # YouTube Shorts Block
          "{34daeb50-c2d2-4f14-886a-7160b24d66a4}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-shorts-block/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Wappalyzer - technology profiler
          "wappalyzer@crunchlabz.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/wappalyzer/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # React DevTools
          "@react-devtools" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/react-devtools/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
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
            default_area = "menupanel";
          };
          # Refined GitHub
          "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/refined-github-/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Fonts Ninja
          "{cade9e47-97ad-4d85-b8a7-002c1f4e8f04}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/fonts-ninja/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # GitHub Repository Size
          "github-repository-size@pranavmangal" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/gh-repo-size/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # GitHub No More
          "github-no-more@ihatereality.space" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/github-no-more/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # ClearURLs - remove tracking from URLs
          "{74145f27-f039-47ce-a470-a662b129930a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Return YouTube Dislikes
          "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/return-youtube-dislikes/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Catppuccin Web File Icons
          "{bbb880ce-43c9-47ae-b746-c3e0096c5b76}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/catppuccin-web-file-icons/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Steam Database
          "firefox-extension@steamdb.info" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/steam-database/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Search Engine Ad Remover
          "@searchengineadremover" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/searchengineadremover/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Decentraleyes - local CDN emulation
          "jid1-BoFifL9Vbdl2zQ@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/decentraleyes/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # TrackMeNot - search privacy
          "trackmenot@mrl.nyu.edu" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/trackmenot/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Custom User Agent Revived
          "{861a3982-bb3b-49c6-bc17-4f50de104da1}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/custom-user-agent-revived/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Chameleon - fingerprint protection
          "{3579f63b-d8ee-424f-bbb6-6d0ce3285e6a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/chameleon-ext/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Bitwarden - password manager
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Solid DevTools
          "{abfd162e-9948-403a-a75c-6e61184e1d47}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/solid-devtools/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Google Lighthouse
          "{cf3dba12-a848-4f68-8e2d-f9fadc0721de}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/google-lighthouse/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Vimium - keyboard navigation
          "{d7742d87-e61d-4b78-b8a1-bb4848a7f12c}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
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
          "browser.sessionstore.warnOnQuit" = {
            Value = false;
            Status = "locked";
          };
          "browser.warnOnQuit" = {
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
          "extensions.allowPrivateBrowsingByDefault" = {
            Value = true;
            Status = "locked";
          };
          "toolkit.legacyUserProfileCustomizations.stylesheets" = {
            Value = true;
            Status = "locked";
          };
          "toolkit.tabbox.switchByScrolling" = {
            Value = true;
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
      };

      profiles."default" = {
        isDefault = true;
        settings = {
          # Zen Browser UI/Workflow Settings
          "zen.workspaces.continue-where-left-off" = true;
          "zen.workspaces.natural-scroll" = true;
          "zen.workspaces.show-workspace-indicator" = false;
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

          .zen-current-workspace-indicator {
            display: none !important;
          }
        '';
        search = {
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
        mods = [
          "253a3a74-0cc4-47b7-8b82-996a64f030d5" # Floating History
          "803c7895-b39b-458e-84f8-a521f4d7a064" # Hide Inactive Workspaces
          "4ab93b88-151c-451b-a1b7-a1e0e28fa7f8" # No Sidebar Scrollbar
          "7190e4e9-bead-4b40-8f57-95d852ddc941" # Tab title fixes
          "b51ff956-6aea-47ab-80c7-d6c047c0d510" # Disable Status Bar
          "a6335949-4465-4b71-926c-4a52d34bc9c0" # Better Find Bar
          "4a222d82-2803-4ed2-a390-90abfce4f195" # Back Fwd Always Hidden
          "cb15abdb-0514-4e09-8ce5-722cf1f4a20f" # Hide Extension Name
          "d8b79d4a-6cba-4495-9ff6-d6d30b0e94fe" # Better Active Tab
          "e122b5d9-d385-4bf8-9971-e137809097d0" # No Top Sites
          "f7c71d9a-bce2-420f-ae44-a64bd92975ab" # Better Unloaded Tabs
          "fd24f832-a2e6-4ce9-8b19-7aa888eb7f8e" # Quietify
          "4c2bec61-7f6c-4e5c-bdc6-c9ad1aba1827" # Vertical Split Tab Groups
          "599a1599-e6ab-4749-ab22-de533860de2c" # Pimp your PiP
          "ae051a40-3e3a-429a-a6f4-199a28b18a75" # Only Reset on Hover
          "4596d8f9-f0b7-4aeb-aa92-851222dc1888" # Only Close on Hover
          "72f8f48d-86b9-4487-acea-eb4977b18f21" # Better CtrlTab Panel
        ];
        containersForce = true;
        containers = {
          Work = {
            color = "orange";
            icon = "briefcase";
            id = 1;
          };
          Manafish = {
            color = "blue";
            icon = "dollar";
            id = 2;
          };
        };
        spacesForce = true;
        spaces = {
          "Default" = {
            id = "540f99e5-b487-46f8-9b1a-a91796f0908e";
            icon = "🫆";
            position = 0;
            theme = {
              type = "gradient";
              colors = [
                {
                  red = 137;
                  green = 180;
                  blue = 250;
                  algorithm = "floating";
                  type = "explicit-lightness";
                }
                {
                  red = 180;
                  green = 190;
                  blue = 254;
                  algorithm = "floating";
                  type = "explicit-lightness";
                }
              ];
              opacity = 0.7;
              texture = 0.3;
            };
          };
          "Work" = {
            id = "f85f6720-823b-47d2-b5a1-03c2fea59187";
            icon = "💼";
            position = 1;
            container = 1;
            theme = {
              type = "gradient";
              colors = [
                {
                  red = 148;
                  green = 226;
                  blue = 213;
                  algorithm = "floating";
                  type = "explicit-lightness";
                }
                {
                  red = 116;
                  green = 199;
                  blue = 236;
                  algorithm = "floating";
                  type = "explicit-lightness";
                }
              ];
              opacity = 0.7;
              texture = 0.3;
            };
          };
          "Manafish" = {
            id = "49f72204-7a80-4b4b-9c5c-99dfc81e0050";
            icon = "💰";
            position = 2;
            container = 2;
            theme = {
              type = "gradient";
              colors = [
                {
                  red = 250;
                  green = 179;
                  blue = 135;
                  algorithm = "floating";
                  type = "explicit-lightness";
                }
                {
                  red = 203;
                  green = 166;
                  blue = 247;
                  algorithm = "floating";
                  type = "explicit-lightness";
                }
              ];
              opacity = 0.7;
              texture = 0.3;
            };
          };
        };
        pins = {
          "T3.chat" = {
            id = "fcfb236d-64d8-4d97-8871-3b720e03ce70";
            url = "https://t3.chat/";
            workspace = "540f99e5-b487-46f8-9b1a-a91796f0908e";
            position = 0;
            isEssential = true;
          };
          "GitHub" = {
            id = "02cdb6d4-bf59-446f-b8ef-3b7a083cb1fb";
            url = "https://github.com/";
            workspace = "540f99e5-b487-46f8-9b1a-a91796f0908e";
            position = 1;
            isEssential = true;
          };
          "YouTube" = {
            id = "67081b25-e880-468c-a14d-7fc037315051";
            url = "https://www.youtube.com/";
            workspace = "540f99e5-b487-46f8-9b1a-a91796f0908e";
            position = 2;
            isEssential = true;
          };
        };
        keyboardShortcutsVersion = 14;
        keyboardShortcuts = [
          {
            id = "key_hideOtherAppsCmdMac";
            key = "h";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_hideThisAppCmdMac";
            key = "h";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_preferencesCmdMac";
            key = ",";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_minimizeWindow";
            key = "m";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_wrToggleCaptureSequenceCmd";
            key = "6";
            modifiers = {
              control = true;
              shift = true;
            };
          }
          {
            id = "key_wrCaptureCmd";
            key = "3";
            modifiers = {
              control = true;
              shift = true;
            };
          }
          {
            id = "key_selectLastTab";
            key = "9";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab8";
            key = "8";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab7";
            key = "7";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab6";
            key = "6";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab5";
            key = "5";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab4";
            key = "4";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab3";
            key = "3";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab2";
            key = "2";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectTab1";
            key = "1";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_undoCloseWindow";
            key = "n";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_restoreLastClosedTabOrWindowOrSession";
            key = "t";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_quitApplication";
            key = "q";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_sanitize_mac";
            keycode = "VK_BACK";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_sanitize";
            keycode = "VK_DELETE";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_screenshot";
            key = "s";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_privatebrowsing";
            key = "p";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_switchTextDirection";
            key = "x";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_showAllTabs";
            keycode = "VK_TAB";
            modifiers = {
              control = true;
              shift = true;
            };
          }
          {
            id = "key_fullZoomReset";
            key = "0";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_fullZoomEnlarge";
            key = "+";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_fullZoomReduce";
            key = "-";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_gotoHistory";
            key = "h";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "toggleSidebarKb";
            key = "z";
            modifiers = {
              control = true;
            };
          }
          {
            id = "viewGenaiChatSidebarKb";
            key = "x";
            modifiers = {
              control = true;
            };
          }
          {
            id = "key_stop_mac";
            key = ".";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_stop";
            keycode = "VK_ESCAPE";
          }
          {
            id = "viewBookmarksToolbarKb";
            key = "b";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "viewBookmarksSidebarKb";
            key = "b";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "manBookmarkKb";
            key = "o";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "bookmarkAllTabsKb";
            key = "d";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "addBookmarkAsKb";
            key = "d";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_findSelection";
            key = "e";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_findPrevious";
            key = "g";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_findAgain";
            key = "g";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_find";
            key = "f";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_viewInfo";
            key = "i";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_viewSourceSafari";
            key = "u";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_viewSource";
            key = "u";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_aboutProcesses";
            keycode = "VK_ESCAPE";
            modifiers = {
              shift = true;
            };
          }
          {
            id = "key_reload_skip_cache";
            key = "r";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_reload";
            key = "r";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_togglePictureInPicture";
            key = "]";
            modifiers = {
              alt = true;
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_toggleReaderMode";
            key = "r";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_exitFullScreen_compat";
            keycode = "VK_F11";
          }
          {
            id = "key_exitFullScreen_old";
            key = "f";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_exitFullScreen";
            key = "f";
            modifiers = {
              control = true;
              meta = true;
            };
          }
          {
            id = "key_enterFullScreen_compat";
            keycode = "VK_F11";
          }
          {
            id = "key_enterFullScreen_old";
            key = "f";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_enterFullScreen";
            key = "f";
            modifiers = {
              control = true;
              meta = true;
            };
          }
          {
            id = "showAllHistoryKb";
            key = "y";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "goHome";
            keycode = "VK_HOME";
            modifiers = {
              alt = true;
            };
          }
          {
            id = "goForwardKb2";
            key = "]";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "goBackKb2";
            key = "[";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "goForwardKb";
            keycode = "VK_RIGHT";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "goBackKb";
            keycode = "VK_LEFT";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_selectAll";
            key = "a";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_delete";
            keycode = "VK_DELETE";
          }
          {
            id = "key_paste";
            key = "v";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_copy";
            key = "c";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_cut";
            key = "x";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_redo";
            key = "z";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_undo";
            key = "z";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_toggleMute";
            key = "m";
            modifiers = {
              control = true;
            };
          }
          {
            id = "key_closeWindow";
            key = "w";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_close";
            key = "w";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "printKb";
            key = "p";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_savePage";
            key = "s";
            modifiers = {
              alt = true;
              shift = true;
              meta = true;
            };
          }
          {
            id = "openFileKb";
            key = "o";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_openAddons";
            key = "a";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_openDownloads";
            key = "j";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_search2";
            key = "f";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_search";
            key = "k";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "focusURLBar";
            key = "l";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_newNavigatorTab";
            key = "t";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "key_newNavigator";
            key = "n";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "zen-compact-mode-toggle";
            key = "s";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "zen-compact-mode-show-sidebar";
            key = "s";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "zen-workspace-switch-10";
            key = "0";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-9";
            key = "9";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-8";
            key = "8";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-7";
            key = "7";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-6";
            key = "6";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-5";
            key = "5";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-4";
            key = "4";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-3";
            key = "3";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-2";
            key = "2";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-switch-1";
            key = "1";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-forward";
            key = "n";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-workspace-backward";
            key = "p";
            modifiers = {
              control = true;
            };
          }
          {
            id = "zen-split-view-grid";
            key = "g";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "zen-split-view-vertical";
            key = "v";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "zen-split-view-horizontal";
            key = "h";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "zen-split-view-unsplit";
            key = "u";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "zen-pinned-tab-reset-shortcut";
            key = "r";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "zen-toggle-sidebar";
            key = "b";
            modifiers = {
              alt = true;
            };
          }
          {
            id = "zen-copy-url";
            key = "c";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "zen-copy-url-markdown";
            key = "c";
            modifiers = {
              alt = true;
              shift = true;
              meta = true;
            };
          }
          {
            id = "zen-toggle-pin-tab";
            key = "d";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "zen-glance-expand";
            key = "o";
            modifiers = {
              meta = true;
            };
          }
          {
            id = "zen-new-empty-split-view";
            key = "*";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "zen-close-all-unpinned-tabs";
            key = "k";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "zen-new-unsynced-window";
            key = "n";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_inspectorMac";
            key = "L";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_accessibility";
            keycode = "VK_F12";
            modifiers = {
              shift = true;
            };
          }
          {
            id = "key_dom";
            key = "w";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_storage";
            keycode = "VK_F9";
            modifiers = {
              shift = true;
            };
          }
          {
            id = "key_performance";
            keycode = "VK_F5";
            modifiers = {
              shift = true;
            };
          }
          {
            id = "key_styleeditor";
            keycode = "VK_F7";
            modifiers = {
              shift = true;
            };
          }
          {
            id = "key_netmonitor";
            key = "e";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_jsdebugger";
            key = "z";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_webconsole";
            key = "k";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_inspector";
            key = "L";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_responsiveDesignMode";
            key = "m";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
          {
            id = "key_browserConsole";
            key = "j";
            modifiers = {
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_browserToolbox";
            key = "i";
            modifiers = {
              alt = true;
              shift = true;
              meta = true;
            };
          }
          {
            id = "key_toggleToolbox";
            key = "i";
            modifiers = {
              alt = true;
              meta = true;
            };
          }
        ];
      };
    };
    xdg.mimeApps = let
      value = let
        zen-browser = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform}.beta;
      in
        zen-browser.meta.desktopFileName;

      associations = builtins.listToAttrs (map (name: {
          inherit name value;
        }) [
          "application/x-extension-shtml"
          "application/x-extension-xhtml"
          "application/x-extension-html"
          "application/x-extension-xht"
          "application/x-extension-htm"
          "x-scheme-handler/unknown"
          "x-scheme-handler/mailto"
          "x-scheme-handler/chrome"
          "x-scheme-handler/about"
          "x-scheme-handler/https"
          "x-scheme-handler/http"
          "application/xhtml+xml"
          "application/json"
          "text/plain"
          "text/html"
        ]);
    in {
      associations.added = associations;
      defaultApplications = associations;
    };
  };
}
