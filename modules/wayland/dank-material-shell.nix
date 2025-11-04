{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs = {
      dankMaterialShell = {
        enable = true;
        enableSystemd = true;
        enableSystemMonitoring = true;
        enableClipboard = true;
        enableVPN = true;
        enableColorPicker = true;
        enableAudioWavelength = true;
        enableCalendarEvents = true;
        enableSystemSound = true;
        default.settings = {
          currentThemeName = "cat-blue";
          customThemeFile = "";
          matugenScheme = "scheme-tonal-spot";
          runUserMatugenTemplates = true;
          matugenTargetMonitor = "";
          dankBarTransparency = 1;
          dankBarWidgetTransparency = 1;
          popupTransparency = 1;
          dockTransparency = 1;
          use24HourClock = true;
          showSeconds = false;
          useFahrenheit = true;
          nightModeEnabled = false;
          weatherLocation = "";
          weatherCoordinates = "59.9419182,10.5028842";
          useAutoLocation = false;
          weatherEnabled = true;
          showLauncherButton = true;
          showWorkspaceSwitcher = true;
          showFocusedWindow = true;
          showWeather = true;
          showMusic = true;
          showClipboard = true;
          showCpuUsage = true;
          showMemUsage = true;
          showCpuTemp = true;
          showGpuTemp = true;
          selectedGpuIndex = 0;
          enabledGpuPciIds = [];
          showSystemTray = true;
          showClock = true;
          showNotificationButton = true;
          showBattery = true;
          showControlCenterButton = true;
          controlCenterShowNetworkIcon = true;
          controlCenterShowBluetoothIcon = true;
          controlCenterShowAudioIcon = true;
          controlCenterWidgets = [
            { id = "wifi"; enabled = true; width = 50; }
            { id = "audioInput"; enabled = true; width = 50; }
            { id = "bluetooth"; enabled = true; width = 50; }
            { id = "audioOutput"; enabled = true; width = 50; }
            { id = "builtin_vpn"; enabled = true; width = 50; }
            { id = "volumeSlider"; enabled = true; width = 50; }
          ];
          showWorkspaceIndex = true;
          workspaceScrolling = false;
          showWorkspacePadding = false;
          showWorkspaceApps = false;
          maxWorkspaceIcons = 3;
          workspacesPerMonitor = true;
          dwlShowAllTags = false;
          workspaceNameIcons = {};
          waveProgressEnabled = true;
          clockCompactMode = false;
          focusedWindowCompactMode = false;
          runningAppsCompactMode = true;
          keyboardLayoutNameCompactMode = false;
          runningAppsCurrentWorkspace = false;
          runningAppsGroupByApp = false;
          clockDateFormat = "MMM d";
          lockDateFormat = "";
          mediaSize = 1;
          dankBarLeftWidgets = [
            "launcherButton"
            "workspaceSwitcher"
            { id = "runningApps"; enabled = true; }
          ];
          dankBarCenterWidgets = [];
          dankBarRightWidgets = [
            { id = "music"; enabled = true; }
            { id = "systemTray"; enabled = true; }
            { id = "memUsage"; enabled = true; }
            { id = "cpuUsage"; enabled = true; }
            { id = "vpn"; enabled = true; }
            { id = "network_speed_monitor"; enabled = true; }
            { id = "controlCenterButton"; enabled = true; }
            { id = "weather"; enabled = true; }
            { id = "clock"; enabled = true; }
            { id = "notificationButton"; enabled = true; }
          ];
          appLauncherViewMode = "list";
          spotlightModalViewMode = "list";
          sortAppsAlphabetically = false;
          networkPreference = "ethernet";
          vpnLastConnected = "";
          iconTheme = "System Default";
          launcherLogoMode = "os";
          launcherLogoCustomPath = "";
          launcherLogoColorOverride = "";
          launcherLogoColorInvertOnMode = false;
          launcherLogoBrightness = 0.5;
          launcherLogoContrast = 1;
          launcherLogoSizeOffset = 0;
          fontFamily = "SFProDisplay Nerd Font";
          monoFontFamily = "SFMono Nerd Font";
          fontWeight = 400;
          fontScale = 1;
          dankBarFontScale = 1;
          notepadUseMonospace = true;
          notepadFontFamily = "";
          notepadFontSize = 14;
          notepadShowLineNumbers = false;
          notepadTransparencyOverride = -1;
          notepadLastCustomTransparency = 0.7;
          soundsEnabled = true;
          useSystemSoundTheme = false;
          soundNewNotification = true;
          soundVolumeChanged = true;
          soundPluggedIn = true;
          gtkThemingEnabled = false;
          qtThemingEnabled = false;
          syncModeWithPortal = true;
          showDock = false;
          dockAutoHide = false;
          dockGroupByApp = false;
          dockOpenOnOverview = false;
          dockPosition = 2;
          dockSpacing = 4;
          dockBottomGap = 0;
          dockIconSize = 40;
          dockIndicatorStyle = "circle";
          cornerRadius = 12;
          notificationOverlayEnabled = false;
          dankBarAutoHide = false;
          dankBarOpenOnOverview = false;
          dankBarVisible = true;
          dankBarSpacing = 4;
          dankBarBottomGap = 0;
          dankBarInnerPadding = 4;
          dankBarSquareCorners = false;
          dankBarNoBackground = false;
          dankBarGothCornersEnabled = false;
          dankBarBorderEnabled = false;
          dankBarBorderColor = "surfaceText";
          dankBarBorderOpacity = 1;
          dankBarBorderThickness = 1;
          popupGapsAuto = true;
          popupGapsManual = 4;
          dankBarPosition = 0;
          lockScreenShowPowerActions = true;
          enableFprint = false;
          maxFprintTries = 3;
          hideBrightnessSlider = false;
          widgetBackgroundColor = "sch";
          surfaceBase = "s";
          wallpaperFillMode = "Fill";
          blurredWallpaperLayer = false;
          blurWallpaperOnOverview = false;
          notificationTimeoutLow = 5000;
          notificationTimeoutNormal = 5000;
          notificationTimeoutCritical = 0;
          notificationPopupPosition = 0;
          osdAlwaysShowValue = false;
          powerActionConfirm = true;
          customPowerActionLock = "";
          customPowerActionLogout = "";
          customPowerActionSuspend = "";
          customPowerActionHibernate = "";
          customPowerActionReboot = "";
          customPowerActionPowerOff = "";
          updaterUseCustomCommand = false;
          updaterCustomCommand = "";
          updaterTerminalAdditionalParams = "";
          screenPreferences = {};
          showOnLastDisplay = {};
          animationSpeed = 1;
          customAnimationDuration = 500;
          acMonitorTimeout = 1200;
          acLockTimeout = 1200;
          acSuspendTimeout = 0;
          acHibernateTimeout = 0;
          batteryMonitorTimeout = 0;
          batteryLockTimeout = 0;
          batterySuspendTimeout = 0;
          batteryHibernateTimeout = 0;
          lockBeforeSuspend = false;
          loginctlLockIntegration = true;
          launchPrefix = "";
          brightnessDevicePins = {};
          configVersion = 1;
        };
        default.session = {};
      };
    };
  };
}
