_: {
  programs.zen-browser.policies = {
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
      Default = "SearXNG";
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
  };
}
