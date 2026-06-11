_: {
  programs.zen-browser.profiles."default" = {
    isDefault = true;
    settings = {
      # Zen Browser UI/Workflow Settings
      "zen.workspaces.continue-where-left-off" = true;
      "zen.workspaces.natural-scroll" = true;
      "zen.workspaces.show-workspace-indicator" = false;
      "zen.view.compact.hide-tabbar" = true;
      "zen.view.compact.hide-toolbar" = true;
      "zen.view.compact.animate-sidebar" = false;
      "zen.welcome-screen.seen" = true;
      "zen.urlbar.behavior" = "float";
      "zen.view.experimental-no-window-controls" = true;
      "zen.view.show-bottom-border" = true;
      "zen.view.show-newtab-button-top" = false;
      "zen.tabs.show-newtab-vertical" = false;
      "zen.theme.color-prefs.amoled" = true;
      "zen.theme.color-prefs.use-workspace-colors" = true;
      "zen.themes.updated-value-observer" = false;
      "zen.splitView.change-on-hover" = true;
      "zen.glance.enabled" = false;
      "zen.glance.activation-method" = "meta";
      "zen.workspaces.force-container-workspace" = true;
      "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;
      "zen.theme.accent-color" = "#89b4fa";

      # Font settings
      "font.name.serif.x-western" = "Source Serif 4";
      "font.name.sans-serif.x-western" = "Inter";
      "font.name.monospace.x-western" = "IosevkaTerm Nerd Font";
    };
    userChrome = ''
      :root {
        --attention-dot-color: rgba(0, 0, 0, 0) !important;
      }

      .zen-current-workspace-indicator {
        display: none !important;
      }
    '';
  };
}
