_: {
  programs.zen-browser.policies.Preferences = {
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

    # Extensions
    "extensions.autoDisableScopes" = {
      Value = 0;
      Status = "locked";
    };

    # Locale settings
    "intl.accept_languages" = {
      Value = "en,nb,nn";
      Status = "locked";
    };
    "intl.locale.requested" = {
      Value = "en-GB";
      Status = "locked";
    };

    # Translations
    "browser.translations.neverTranslateLanguages" = {
      Value = "en,nb,nn";
      Status = "locked";
    };
  };
}
