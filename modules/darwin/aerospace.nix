_: {
  services = {
    aerospace = {
      enable = true;
      settings = {
        config-version = 2;

        gaps = {
          inner = {
            horizontal = 6;
            vertical = 6;
          };
          outer = {
            left = 6;
            bottom = 6;
            top = 6;
            right = 6;
          };
        };

        persistent-workspaces = ["1" "2" "3" "4" "5" "6" "7" "8" "9"];
        on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];
        on-window-detected = [
          {
            "if".app-name-regex-substring = "^(Calculator|Archive Utility)$";
            run = "layout floating";
          }
          {
            "if".app-name-regex-substring = "^Zen$";
            run = "move-node-to-workspace 2";
          }
          {
            "if".app-name-regex-substring = "^(Proton Pass|OpenCode|T3 Code.*)$";
            run = "move-node-to-workspace 3";
          }
          {
            "if".app-name-regex-substring = "^(Proton Mail|Thunderbird|LibreOffice)$";
            run = "move-node-to-workspace 4";
          }
          {
            "if".app-name-regex-substring = "^(Messages|FaceTime|Element|Legcord|Slack|Signal)$";
            run = "move-node-to-workspace 5";
          }
          {
            "if".app-name-regex-substring = "^(Inkscape|Gimp|Scribus|DaVinci Resolve|FreeCAD|OrcaSlicer)$";
            run = "move-node-to-workspace 6";
          }
          {
            "if".app-name-regex-substring = "^(Music|Photos|Supersonic)$";
            run = "move-node-to-workspace 7";
          }
        ];

        mode.main.binding = {
          # Focus window
          alt-h = "focus left";
          alt-j = "focus down";
          alt-k = "focus up";
          alt-l = "focus right";

          # Move window
          alt-shift-h = "move left";
          alt-shift-j = "move down";
          alt-shift-k = "move up";
          alt-shift-l = "move right";

          # Resize window
          alt-left = "resize width -20";
          alt-right = "resize width +20";
          alt-up = "resize height -20";
          alt-down = "resize height +20";

          # Switch to workspace
          alt-1 = "workspace --auto-back-and-forth 1";
          alt-2 = "workspace --auto-back-and-forth 2";
          alt-3 = "workspace --auto-back-and-forth 3";
          alt-4 = "workspace --auto-back-and-forth 4";
          alt-5 = "workspace --auto-back-and-forth 5";
          alt-6 = "workspace --auto-back-and-forth 6";
          alt-7 = "workspace --auto-back-and-forth 7";
          alt-8 = "workspace --auto-back-and-forth 8";
          alt-9 = "workspace --auto-back-and-forth 9";

          # Move window to workspace
          alt-shift-1 = "move-node-to-workspace --focus-follows-window 1";
          alt-shift-2 = "move-node-to-workspace --focus-follows-window 2";
          alt-shift-3 = "move-node-to-workspace --focus-follows-window 3";
          alt-shift-4 = "move-node-to-workspace --focus-follows-window 4";
          alt-shift-5 = "move-node-to-workspace --focus-follows-window 5";
          alt-shift-6 = "move-node-to-workspace --focus-follows-window 6";
          alt-shift-7 = "move-node-to-workspace --focus-follows-window 7";
          alt-shift-8 = "move-node-to-workspace --focus-follows-window 8";
          alt-shift-9 = "move-node-to-workspace --focus-follows-window 9";

          # Toggle floating window
          alt-0 = "layout floating tiling";

          # Open WezTerm
          alt-enter = "exec-and-forget open -na WezTerm --args start --always-new-process";
          alt-shift-enter = "exec-and-forget open -na WezTerm --args start --always-new-process -e sh -c 'yazi'";
        };
      };
    };
  };
}
