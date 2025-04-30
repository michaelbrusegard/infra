{ pkgs, ... }: {
  services = {
    nix-daemon.enable = true;
    yabai = {
      enable = true;
      enableScriptingAddition = true;
      config = {
        layout = "bsp";
        focus_follows_mouse = "off";
        mouse_modifier = "alt";
        top_padding = 6;
        bottom_padding = 12;
        left_padding = 12;
        right_padding = 12;
        window_gap = 6;
        insert_feedback_color = "0xff89b4fa";
      };
      extraConfig = ''
        # Space layout settings
        yabai -m config --space 3 layout stack
        yabai -m config --space 9 layout float

        # Application rules
        yabai -m rule --add app="^(Calculator|System Settings|Archive Utility)$" manage=off
        yabai -m rule --add app="^(Safari|Zen Browser)$" space=2
        yabai -m rule --add app="^(Proton Mail|Proton Pass)$" space=3
        yabai -m rule --add app="^(Notes|Obsidian)$" space=4
        yabai -m rule --add app="^(Messages|FaceTime|Element|Messenger|Legcord|Slack)$" space=5
        yabai -m rule --add app="^(Music|TV|Photos)$" space=6
        yabai -m rule --add app="^(Affinity Photo 2|Affinity Designer 2|Affinity Publisher 2)$" space=7

        # Make sure there are 9 spaces
        current_spaces=$(yabai -m query --spaces | ${pkgs.jq}/bin/jq length)
        spaces_to_create=$((9 - current_spaces))
        spaces_to_delete=$((current_spaces - 9))

        if [[ $spaces_to_create -gt 0 ]]; then
            for i in $(seq 1 $spaces_to_create); do
                yabai -m space --create
            done
        fi

        if [[ $spaces_to_delete -gt 0 ]]; then
            for i in $(seq 1 $spaces_to_delete); do
                last_space_id=$(yabai -m query --spaces | ${pkgs.jq}/bin/jq '.[-1].index')
                yabai -m space --destroy $last_space_id
            done
        fi
      '';
    };
    skhd = {
      enable = true;
      package = pkgs.skhd;
      skhdConfig = ''
        # Focus window
        alt - h : yabai -m window --focus west || yabai -m display --focus west
        alt - l : yabai -m window --focus east || yabai -m display --focus east
        alt - j : yabai -m window --focus stack.next || yabai -m window --focus south
        alt - k : yabai -m window --focus stack.prev || yabai -m window --focus north

        # Move window
        alt + shift - h : yabai -m window --swap west || yabai -m window --display west
        alt + shift - l : yabai -m window --swap east || yabai -m window --display east
        alt + shift - j : yabai -m window --swap south
        alt + shift - k : yabai -m window --swap north

        # Resize window
        alt - left : yabai -m window --resize left:-20:0 || yabai -m window --resize right:-20:0
        alt - down : yabai -m window --resize bottom:0:20 || yabai -m window --resize top:0:20
        alt - up : yabai -m window --resize top:0:-20 || yabai -m window --resize bottom:0:-20
        alt - right : yabai -m window --resize right:20:0 || yabai -m window --resize left:20:0

        # Switch to specific space
        alt - 1 : yabai -m space --focus 1 || yabai -m space --focus recent
        alt - 2 : yabai -m space --focus 2 || yabai -m space --focus recent
        alt - 3 : yabai -m space --focus 3 || yabai -m space --focus recent
        alt - 4 : yabai -m space --focus 4 || yabai -m space --focus recent
        alt - 5 : yabai -m space --focus 5 || yabai -m space --focus recent
        alt - 6 : yabai -m space --focus 6 || yabai -m space --focus recent
        alt - 7 : yabai -m space --focus 7 || yabai -m space --focus recent
        alt - 8 : yabai -m space --focus 8 || yabai -m space --focus recent
        alt - 9 : yabai -m space --focus $(yabai -m query --spaces | ${pkgs.jq}/bin/jq '.[-1].index')

        # Move window to specific space
        alt + shift - 1 : yabai -m window --space 1 && yabai -m space --focus 1
        alt + shift - 2 : yabai -m window --space 2 && yabai -m space --focus 2
        alt + shift - 3 : yabai -m window --space 3 && yabai -m space --focus 3
        alt + shift - 4 : yabai -m window --space 4 && yabai -m space --focus 4
        alt + shift - 5 : yabai -m window --space 5 && yabai -m space --focus 5
        alt + shift - 6 : yabai -m window --space 6 && yabai -m space --focus 6
        alt + shift - 7 : yabai -m window --space 7 && yabai -m space --focus 7
        alt + shift - 8 : yabai -m window --space 8 && yabai -m space --focus 8
        alt + shift - 9 : LAST_SPACE=$(yabai -m query --spaces | ${pkgs.jq}/bin/jq '.[-1].index'); yabai -m window --space $LAST_SPACE && yabai -m space --focus $LAST_SPACE

        # Toggle Floating Window
        alt - 0 : yabai -m window --toggle float

        # Change between tiled and stacked layout for space
        alt - comma : yabai -m space --layout bsp
        alt - slash : yabai -m space --layout stack

        # System
        alt - return : wezterm start --always-new-process
        alt + shift - return : wezterm start --always-new-process -e sh -c 'yazi'
        super - space : open -a "Raycast"
        super - q : yabai -m window --close
      '';
    };
    jankyborders = {
      enable = true;
      hidpi = true;
      style = "round";
      active_color = "0xff89b4fa";
      inactive_color = "0xff45475a";
      width = 6;
    };
  };
}
