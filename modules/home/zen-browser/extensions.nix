_: {
  programs.zen-browser.policies = {
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
      # DeArrow - crowdsourced YouTube titles/thumbnails
      "deArrow@ajay.app" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/dearrow/latest.xpi";
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
      "@ffn" = {
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
      # Get cookies.txt LOCALLY
      "{ac87cfd8-47b1-4401-b32e-f033af5ed96b}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/get-cookies-txt-locally/latest.xpi";
        installation_mode = "force_installed";
        default_area = "menupanel";
      };
      # Return YouTube Dislikes
      "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/return-youtube-dislikes/latest.xpi";
        installation_mode = "force_installed";
        default_area = "menupanel";
      };
      # Steam Database
      "firefox-extension@steamdb.info" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/steam-database/latest.xpi";
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
      "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
        installation_mode = "force_installed";
        default_area = "menupanel";
      };
      # Material Icons for Github
      "{eac6e624-97fa-4f28-9d24-c06c9b8aa713}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/material-icons-for-github/latest.xpi";
        installation_mode = "force_installed";
        default_area = "menupanel";
      };
    };
    "3rdparty".Extensions = {
      "uBlock0@raymondhill.net" = {
        adminSettings = builtins.toJSON {
          userSettings = {
            uiTheme = "dark";
            advancedUserEnabled = true;
            webrtcIPAddressHidden = true;
          };
          selectedFilterLists = [
            "user-filters"
            "ublock-filters"
            "ublock-badware"
            "ublock-privacy"
            "ublock-unbreak"
            "easylist"
            "easyprivacy"
            "urlhaus-1"
            "plowe-0"
            "ublock-quick-fixes"
            "ublock-annoyances"
          ];
        };
      };
    };
  };
}
