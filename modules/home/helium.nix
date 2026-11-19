{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # Chrome Web Store IDs. Helium bundles uBlock Origin and proxies store
  # downloads through its own services.
  extensions = {
    floccus = "fnaicdffflnofjppbagibeoednhnbjhg";
    bitwarden = "nngceckbapebfimnlniiiahkandclblb";
    vimium = "dbepggeogbaibhgnhhndojpepiihcmeb";
    sponsorblock = "mnjggcdmjocbbbhaepdhchncahnbgone";
    dearrow = "enamippconapkdmgfgjchkhakpfinmaj";
    return-youtube-dislike = "gebbhagfogifgggkldgodflihgfeippi";
    youtube-shorts-block = "jiaopdjbehhjgokpphdfgmapkobbnmjp";
    refined-github = "hlepfoohegkhhmjieoechaddaejaokhf";
    react-devtools = "fmkadmapgofadopljbjfkapdkoienihi";
  };

  settings = {
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "DuckDuckGo";
    DefaultSearchProviderKeyword = "ddg";
    DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
  };

  helium = pkgs.helium-browser.override {
    policies =
      settings
      // {
        ExtensionInstallForcelist = lib.attrValues extensions;
      };
  };
in {
  # home.persistence only exists on hosts with impermanence, so it is left out
  # rather than mkIf'd; both conditions are module arguments, not config.
  config = lib.mkMerge (
    lib.optionals (!isWsl) [
      {
        home.packages = [
          (
            if isDarwin
            then pkgs.brewCasks.helium-browser
            else helium
          )
        ];
      }

      # macOS only forces policies from MDM profiles; preferences in Helium's
      # domain apply as recommended defaults the user can still change, and
      # extensions are offered through the External Extensions directory.
      (lib.mkIf isDarwin {
        targets.darwin.defaults."net.imput.helium" = settings;
        home.file = lib.mapAttrs' (_: id:
          lib.nameValuePair "Library/Application Support/net.imput.helium/External Extensions/${id}.json" {
            # Helium only routes installs through its proxy (and its
            # consent check) for its own placeholder store URL.
            text = builtins.toJSON {
              external_update_url = "https://update-url-to-be-replaced.qjz9zk";
            };
          })
        extensions;
      })
    ]
    ++ lib.optional (!isWsl && homePersistenceRoot != null) {
      home.persistence.${homePersistenceRoot}.directories = [
        ".config/net.imput.helium"
      ];
    }
  );
}
