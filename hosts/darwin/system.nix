{ pkgs, userName, ... }: {
  system = {
    stateVersion = 5;
    defaults = {
      ".GlobalPreferences" = {
        "com.apple.mouse.scaling" = -1.0;
      };
      ActivityMonitor = {
        IconType = 5;
        OpenMainWindow = true;
        ShowCategory = 100;
        SortColumn = "CPUUsage";
        SortDirection = 0;
      };
      alf = {
        globalstate = 1;
      };
      controlcenter = {
        AirDrop = false;
        BatteryShowPercentage = true;
        Bluetooth = false;
        Display = false;
        FocusModes = false;
        NowPlaying = false;
        Sound = false;
      };
      dock = {
        autohide = true;
        autohide-delay = 2147483647.0;
        autohide-time-modifier = 0.0;
        expose-animation-duration = 0.0;
        launchanim = false;
        mineffect = "scale";
        minimize-to-application = true;
        mru-spaces = false;
        orientation = "left";
        persistent-apps = [];
        persistent-others = [];
        show-process-indicators = false;
        show-recents = false;
        static-only = true;
        tilesize = 64;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
      };
      finder = {
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirst = true;
        _FXSortFoldersFirstOnDesktop = true;
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "NLsv";
        FXRemoveOldTrashItems = true;
        NewWindowTarget = "Desktop";
        ShowExternalHardDrivesOnDesktop = false;
        ShowHardDrivesOnDesktop = false;
        ShowMountedServersOnDesktop = false;
        ShowRemovableMediaOnDesktop = false;
      };
      hitoolbox.AppleFnUsageType = "Do Nothing";
      LaunchServices.LSQuarantine = false;
      loginwindow = {
        DisableConsoleAccess = true;
        GuestEnabled = false;
        SHOWFULLNAME = true;
        PowerOffDisabledWhileLoggedIn = true;
        RestartDisabled = true;
        RestartDisabledWhileLoggedIn = true;
        ShutDownDisabled = true;
        ShutDownDisabledWhileLoggedIn = true;
        SleepDisabled = true;
      };
      menuExtraClock = {
        Show24Hour = true;
        ShowDate = 1;
        ShowDayOfMonth = true;
      };
      NSGlobalDomain = {
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.feedback" = 0;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.springing.delay" = 0.0;
        "com.apple.springing.enabled" = false;
        "com.apple.trackpad.forceClick" = false;
        AppleEnableMouseSwipeNavigateWithScrolls = false;
        AppleEnableSwipeNavigateWithScrolls = false;
        AppleICUForce24HourTime = true;
        AppleInterfaceStyle = "Dark";
        AppleKeyboardUIMode = 3;
        AppleMeasurementUnits = "Centimeters";
        AppleMetricUnits = 1;
        ApplePressAndHoldEnabled = false;
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        AppleShowScrollBars = "Always";
        AppleSpacesSwitchOnActivate = false;
        AppleTemperatureUnit = "Celsius";
        AppleWindowTabbingMode = "manual";
        InitialKeyRepeat = 10;
        KeyRepeat = 1;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticInlinePredictionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = false;
        NSDisableAutomaticTermination = true;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        NSTableViewDefaultSizeMode = 2;
        NSUseAnimatedFocusRing = false;
        NSWindowResizeTime = 0.0;
        NSWindowShouldDragOnGesture = true;
        PMPrintingExpandedStateForPrint = true;
        PMPrintingExpandedStateForPrint2 = true;
      };
      screencapture = {
        disable-shadow = true;
        include-date = false;
        location = "~/Pictures/screenshots";
        show-thumbnail = false;
        type = "png";
      };
      screensaver = {
        askForPassword = true;
        askForPasswordDelay = 0;
      };
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
      spaces.spans-displays = false;
      trackpad = {
        ActuationStrength = 0;
        Clicking = true;
        Dragging = false;
        FirstClickThreshold = 0;
        SecondClickThreshold = 0;
        TrackpadRightClick = true;
        TrackpadThreeFingerTapGesture = 0;
      };
      universalaccess = {
        reduceMotion = true;
        reduceTransparency = true;
      };
      WindowManager = {
        AppWindowGroupingBehavior = false;
        EnableStandardClickToShowDesktop = false;
        EnableTiledWindowMargins = false;
        EnableTilingByEdgeDrag = false;
        EnableTilingOptionAccelerator = false;
        EnableTopTilingByEdgeDrag = false;
        GloballyEnabled = false;
        HideDesktop = true;
        StageManagerHideWidgets = true;
        StandardHideDesktopIcons = true;
        StandardHideWidgets = true;
      };
      CustomSystemPreferences = {
        "com.apple.BluetoothAudioAgent" = {
          "Apple Bitpool Max (editable)" = 80;
          "Apple Bitpool Min (editable)" = 80;
          "Apple Initial Bitpool (editable)" = 80;
          "Apple Initial Bitpool Min (editable)" = 80;
          "Negotiated Bitpool" = 80;
          "Negotiated Bitpool Max" = 80;
          "Negotiated Bitpool Min" = 80;
        };
        "com.apple.TimeMachine" = {
          DoNotOfferNewDisksForBackup = true;
        };
        "com.apple.DiskArbitration.diskarbitrationd" = {
          DADisableEjectNotification = true;
        };
      };
      CustomUserPreferences = {
        "com.apple.Safari" = {
          AlwaysRestoreSessionAtLaunch = false;
          AutoOpenSafeDownloads = false;
          ShowStandaloneTabBar = false;
          TabCreationPolicy = 1;
          SearchProviderShortName = "DuckDuckGo";
          PrivateSearchProviderShortName = "DuckDuckGo";
          WBSLastPrivateSearchEngineStringExplicitlyChosenByUserKey = "com.duckduckgo";
          UniversalSearchEnabled = true;
          WarnAboutFraudulentWebsites = true;
          BlockStoragePolicy = 2;
          WBSPrivacyProxyAvailabilityTraffic = 33422572;
          ShowFullURLInSmartSearchField = true;
          NeverUseBackgroundColorInToolbar = false;
          EnableEnhancedPrivacyInPrivateBrowsing = true;
          EnableEnhancedPrivacyInRegularBrowsing = true;
          ShowFavoritesBar-v2 = false;
          DebugSnapshotsUpdatePolicy = 2;
          FindOnPageMatchesWordStartsOnly = false;
          SuppressSearchSuggestions = true;
          WebContinuousSpellCheckingEnabled = true;
          WebAutomaticSpellingCorrectionEnabled = false;
          InstallExtensionUpdatesAutomatically = true;
        };
        "com.apple.messageshelper.MessageController" = {
          SOInputLineSettings = {
            automaticEmojiSubstitutionEnablediMessage = false;
            automaticQuoteSubstitutionEnabled = false;
            continuousSpellCheckingEnabled = false;
          };
        };
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        "com.apple.frameworks.diskimages" = {
          skip-verify = true;
          skip-verify-locked = true;
          skip-verify-remote = true;
        };
        "com.apple.NetworkBrowser" = {
          BrowseAllInterfaces = true;
        };
        "com.jordanbaird.Ice" = {
          AutoRehide = true;
          CanToggleAlwaysHiddenSection = true;
          EnableAlwaysHiddenSection = true;
          IceBarLocation = 0;
          ItemSpacingOffset = 0.0;
          RehideInterval = 15;
          RehideStrategy = 0;
          ShowAllSectionsOnUserDrag = true;
          ShowIceIcon = true;
          ShowOnClick = true;
          ShowOnHover = false;
          ShowOnHoverDelay = 0.2;
          ShowOnScroll = true;
          ShowSectionDividers = false;
          TempShowInterval = 15;
          UseIceBar = false;
          SUAutomaticallyUpdate = false;
          SUEnableAutomaticallyChecks = false;
        };
      };
    };
    keyboard = {
      enableKeyMapping = true;
      nonUS.remapTilde = true;
    };
    startup.chime = false;
    activationScripts = {
      createLogsDir.text = ''
        mkdir -p /Users/${userName}/.logs
        chown ${userName} /Users/${userName}/.logs
      '';
      podmanInit.text = ''
        if ! ${pkgs.podman}/bin/podman machine list | grep -q 'podman-machine-default'; then
          echo "Initializing Podman machine..."
          ${pkgs.podman}/bin/podman machine init
        fi
      '';
      podmanDockerCompat.text = ''
          mkdir -p $HOME/.config/containers
          echo "[engine]
      compatible = true" > $HOME/.config/containers/containers.conf
          mkdir -p $HOME/bin
          ln -sf ${pkgs.podman}/bin/podman $HOME/bin/docker
          mkdir -p $HOME/.local/share/containers/podman/machine
          mkdir -p $HOME/.docker
          ln -sf $HOME/.local/share/containers/podman/machine/podman.sock ~/.docker/docker.sock
        '';
    };
  };
}
