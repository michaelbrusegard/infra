{
  flake.modules.homeManager.helium =
    {
      pkgs,
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin;

      # Chrome Web Store IDs. Helium bundles uBlock Origin and proxies store
      # downloads through its own services.
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
      helium = pkgs.helium-browser.override { inherit policies; };
      # On trial beside Helium, with the same policies, before replacing it.
      ardia = pkgs.ardia.override { inherit policies; };
    in
    {
      # home.persistence only exists on hosts with impermanence, so it is left out
      # rather than mkIf'd; both conditions are module arguments, not config.
      config = lib.mkMerge (
        [
          {
            home.packages =
              if isDarwin then
                [ pkgs.brewCasks.helium-browser ]
              else
                [
                  helium
                  ardia
                ];
          }

          # macOS only forces policies from MDM profiles; preferences in Helium's
          # domain apply as recommended defaults the user can still change, and
          # extensions are offered through the External Extensions directory.
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
            ] (_: [ "helium.desktop" ]);
          })

          (lib.mkIf isDarwin {
            targets.darwin.defaults."net.imput.helium" = darwinSettings;
            home.file = lib.mapAttrs' (
              _: id:
              lib.nameValuePair "Library/Application Support/net.imput.helium/External Extensions/${id}.json" {
                # Helium only routes installs through its proxy (and its
                # consent check) for its own placeholder store URL.
                text = builtins.toJSON {
                  external_update_url = "https://update-url-to-be-replaced.qjz9zk";
                };
              }
            ) extensions;
          })
        ]
        ++ lib.optional (homePersistenceRoot != null) {
          home.persistence.${homePersistenceRoot}.directories = [
            ".config/net.imput.helium"
            ".config/ardia"
            # Ardia unpacks its command-line tool here on first start.
            ".local/share/ardia"
          ];
        }
      );
    };
}
