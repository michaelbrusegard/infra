{
  flake.modules.darwin.aerospace =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.users.users.${config.system.primaryUser}.home;
      kitty = lib.getExe pkgs.kitty;
    in
    {
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

            persistent-workspaces = [
              "1"
              "2"
              "3"
              "4"
              "5"
              "6"
              "7"
              "8"
              "9"
            ];
            on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];
            on-window-detected = [
              {
                "if".app-name-regex-substring = "^(Calculator|Archive Utility)$";
                run = "layout floating";
              }
              {
                "if".app-id = "com.apple.iphonesimulator";
                run = "layout floating";
              }
              {
                "if".app-name-regex-substring = "^qemu-system-aarch64$";
                run = "layout floating";
              }
              {
                "if".app-name-regex-substring = "^Ardia$";
                run = "move-node-to-workspace 2";
              }
              {
                "if".app-name-regex-substring = "^T3 Code.*$";
                run = "move-node-to-workspace 1";
              }
              {
                "if".app-name-regex-substring = "^Bulwark$";
                run = "move-node-to-workspace 3";
              }
              {
                "if".app-name-regex-substring = "^(Messages|FaceTime|Discord|Slack|Signal)$";
                run = "move-node-to-workspace 5";
              }
              {
                "if".app-name-regex-substring = "^OrcaSlicer$";
                run = "move-node-to-workspace 6";
              }
              {
                "if".app-name-regex-substring = "^(Music|Photos|Feishin)$";
                run = "move-node-to-workspace 7";
              }
            ];

            mode.main.binding = {
              alt-h = "focus left";
              alt-j = "focus down";
              alt-k = "focus up";
              alt-l = "focus right";

              alt-shift-h = "move left";
              alt-shift-j = "move down";
              alt-shift-k = "move up";
              alt-shift-l = "move right";

              alt-left = "resize width -20";
              alt-right = "resize width +20";
              alt-up = "resize height -20";
              alt-down = "resize height +20";

              alt-1 = "workspace --auto-back-and-forth 1";
              alt-2 = "workspace --auto-back-and-forth 2";
              alt-3 = "workspace --auto-back-and-forth 3";
              alt-4 = "workspace --auto-back-and-forth 4";
              alt-5 = "workspace --auto-back-and-forth 5";
              alt-6 = "workspace --auto-back-and-forth 6";
              alt-7 = "workspace --auto-back-and-forth 7";
              alt-8 = "workspace --auto-back-and-forth 8";
              alt-9 = "workspace --auto-back-and-forth 9";

              alt-shift-1 = "move-node-to-workspace --focus-follows-window 1";
              alt-shift-2 = "move-node-to-workspace --focus-follows-window 2";
              alt-shift-3 = "move-node-to-workspace --focus-follows-window 3";
              alt-shift-4 = "move-node-to-workspace --focus-follows-window 4";
              alt-shift-5 = "move-node-to-workspace --focus-follows-window 5";
              alt-shift-6 = "move-node-to-workspace --focus-follows-window 6";
              alt-shift-7 = "move-node-to-workspace --focus-follows-window 7";
              alt-shift-8 = "move-node-to-workspace --focus-follows-window 8";
              alt-shift-9 = "move-node-to-workspace --focus-follows-window 9";

              alt-0 = "layout floating tiling";

              alt-enter = "exec-and-forget ${kitty} --working-directory ${home}";
              alt-shift-enter = "exec-and-forget /usr/bin/open ${home}";
            };
          };
        };
      };
    };
}
