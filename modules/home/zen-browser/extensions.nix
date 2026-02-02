_: {
  programs.zen-browser.policies.ExtensionSettings = {
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
}
