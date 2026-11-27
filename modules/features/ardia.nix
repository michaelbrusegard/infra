{
  flake.modules.nixos.ardia =
    { pkgs, ... }:
    {
      # Ardia asks polkit for this action before it copies the sync recovery
      # words or shows a saved password. Its .deb registers the action; the
      # AppImage does not, and without it those buttons do nothing.
      environment.systemPackages = [
        (pkgs.writeTextDir "share/polkit-1/actions/dev.ardia.linux.policy" (
          builtins.readFile ../../packages/ardia/reauth.policy
        ))
      ];
    };

  flake.modules.homeManager.ardia =
    {
      pkgs,
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin;

      # Chrome Web Store IDs.
      extensions = {
        bitwarden = "nngceckbapebfimnlniiiahkandclblb";
        vimium = "dbepggeogbaibhgnhhndojpepiihcmeb";
        sponsorblock = "mnjggcdmjocbbbhaepdhchncahnbgone";
        dearrow = "enamippconapkdmgfgjchkhakpfinmaj";
        return-youtube-dislike = "gebbhagfogifgggkldgodflihgfeippi";
        youtube-shorts-block = "jiaopdjbehhjgokpphdfgmapkobbnmjp";
        refined-github = "hlepfoohegkhhmjieoechaddaejaokhf";
        material-icons-for-github = "bggfcpfjbdkhfhfmkjpbhnkhnpjjeomc";
        enhanced-github = "anlikcnbgdeidpacdbdljnabclhahhmd";
        proton-vpn = "jplgfhpmjnbigmhklmmbgecoobifkmpa";
        fonts-ninja = "eljapbgkmlngdpckoiiibecpemleclhh";
        wappalyzer = "gppongmhjkpfnbhagpmjfkannfbllamg";
      };

      settings = {
        DefaultSearchProviderEnabled = true;
        DefaultSearchProviderName = "DuckDuckGo";
        DefaultSearchProviderKeyword = "ddg";
        DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
        SearchSuggestEnabled = false;
        PasswordManagerEnabled = false;
        AutofillSettings = [
          {
            url_pattern = "*";
            blocked_types = [ "all" ];
          }
        ];
        NetworkPredictionOptions = 2;
        HttpsOnlyMode = "force_balanced_enabled";
        BlockThirdPartyCookies = true;
        DefaultBrowserSettingEnabled = false;
        PromptForDownloadLocation = false;
        RestoreOnStartup = 1;
      };

      # Unmanaged Macs only take recommended policies, and RestoreOnStartup is
      # filtered there as sensitive, so set it by hand on macOS.
      darwinSettings = removeAttrs settings [ "RestoreOnStartup" ];

      policies = settings // {
        ExtensionInstallForcelist = lib.attrValues extensions;
      };
      ardia = pkgs.ardia.override { inherit policies; };

      # Ardia reads ⌘ as Ctrl and ⌃ as Super on Linux, which is where kanata puts
      # Cmd and Control, so one file gives the same keys on both machines. These
      # are its Linux defaults that differ from the Mac ones; the glyphs are its
      # own Mac notation. Clear Browsing Data is unbound because kanata sends its
      # Ctrl+Shift+Backspace for Cmd+Backspace, delete to line start.
      shortcuts = {
        "tabSwitcher:forward" = "⌃⇥";
        "tabSwitcher:backward" = "⌃⇧⇥";
        openSplitPane = "⌃⇧=";
        openSplitPaneBelow = "⌃⇧-";
        moveSplitPaneLeft = "⌃⌥←";
        moveSplitPaneRight = "⌃⌥→";
        moveSplitPaneUp = "⌃⌥↑";
        moveSplitPaneDown = "⌃⌥↓";
        downloads = "⇧⌘J";
        javaScriptConsole = "⌥⌘J";
        devTools = "⌥⌘I";
        emailPageLocation = "⇧⌘I";
        jumpToSelection = "⌘J";
        clearBrowsingData = "";
      };
    in
    {
      # home.persistence only exists on hosts with impermanence, so it is left out
      # rather than mkIf'd; both conditions are module arguments, not config.
      config = lib.mkMerge (
        [
          {
            # The Mac gets Ardia from its Homebrew cask.
            home.packages = lib.optional (!isDarwin) ardia;

            xdg.configFile.${if isDarwin then "ardia/config.json" else "ardia/config/config.json"}.text =
              builtins.toJSON
                { settings = { inherit shortcuts; }; };
          }

          (lib.mkIf (!isDarwin) {
            xdg.mimeApps.defaultApplications = lib.genAttrs [
              "text/html"
              "application/xhtml+xml"
              "application/x-extension-htm"
              "application/x-extension-html"
              "application/x-extension-shtml"
              "application/x-extension-xht"
              "application/x-extension-xhtml"
              "x-scheme-handler/http"
              "x-scheme-handler/https"
              "x-scheme-handler/about"
              "x-scheme-handler/unknown"
            ] (_: [ "ardia.desktop" ]);
          })

          # macOS only forces policies from MDM profiles; preferences in Ardia's
          # domain apply as recommended defaults the user can still change, and
          # extensions are offered through the External Extensions directory.
          (lib.mkIf isDarwin {
            targets.darwin.defaults."com.ardia.browser" = darwinSettings;
            home.file = lib.mapAttrs' (
              _: id:
              lib.nameValuePair
                "Library/Application Support/com.ardia.browser/Chromium/External Extensions/${id}.json"
                {
                  text = builtins.toJSON {
                    external_update_url = "https://clients2.google.com/service/update2/crx";
                  };
                }
            ) extensions;
          })
        ]
        ++ lib.optional (homePersistenceRoot != null) {
          home.persistence.${homePersistenceRoot}.directories = [
            ".config/ardia"
            # Ardia unpacks its command-line tool here on first start.
            ".local/share/ardia"
          ];
        }
      );
    };
}
