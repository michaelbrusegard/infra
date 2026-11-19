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

  # brew-api pins an old cask (0.14.9.1); follow upstream releases instead.
  heliumDarwin = let
    version = "0.22.1.1";
    artifact =
      if pkgs.stdenv.hostPlatform.isAarch64
      then {
        arch = "arm64";
        hash = "sha256-jCNEgMASI8nbyejcW8W+CLjkNBQ31i2unXWUK1lPvVE=";
      }
      else {
        arch = "x86_64";
        hash = "sha256-DZgrEdfUTWEvNndL49azxFH1g/8kzwCeKHv3NTFRUgI=";
      };
  in
    pkgs.brewCasks.helium-browser.overrideAttrs {
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/imputnet/helium-macos/releases/download/${version}/helium_${version}_${artifact.arch}-macos.dmg";
        inherit (artifact) hash;
      };
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
            then heliumDarwin
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
