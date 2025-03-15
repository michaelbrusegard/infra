{ pkgs, ... }: {
  services = {
    yabai = {
      enable = true;
      enableScriptingAddition = true;
      config = {
        layout = "bsp";
        focus_follows_mouse = "autoraise";
        mouse_modifier = "alt";
        top_padding = 6;
        bottom_padding = 12;
        left_padding = 12;
        right_padding = 12;
        window_gap = 6;
        insert_feedback_color = "0xFF007AFF";
      };
      extraConfig = ''
        # Space labels
        yabai -m space 1 --label Code
        yabai -m space 2 --label Web
        yabai -m space 3 --label Mail
        yabai -m space 4 --label Notes
        yabai -m space 5 --label Social
        yabai -m space 6 --label Media
        yabai -m space 7 --label Creative
        yabai -m space 8 --label "General 1"
        yabai -m space 9 --label "General 2"

        # Space layout settings
        yabai -m config --space Mail layout stack
        yabai -m config --space "General 2" layout float

        # Application rules
        yabai -m rule --add app="^(Calculator|System Settings|Archive Utility)$" manage=off
        yabai -m rule --add app="^(Safari|Zen Browser)$" space=Web
        yabai -m rule --add app="^(Proton Mail)$" space=Mail
        yabai -m rule --add app="^(Messages|FaceTime|Element|Messenger|Legcord|Slack)$" space=Social
        yabai -m rule --add app="^(Notes|Obsidian)$" space=Notes
        yabai -m rule --add app="^(Music|TV|Photos)$" space=Media
        yabai -m rule --add app="^(Affinity Photo 2|Affinity Designer 2|Affinity Publisher 2)$" space=Creative

        # Make sure there are 9 spaces
        current_spaces=$(yabai -m query --spaces | jq length)
        spaces_to_create=$((9 - current_spaces))
        spaces_to_delete=$((current_spaces - 9))

        if [[ $spaces_to_create -gt 0 ]]; then
            for i in $(seq 1 $spaces_to_create); do
                yabai -m space --create
            done
        fi

        if [[ $spaces_to_delete -gt 0 ]]; then
            for i in $(seq 1 $spaces_to_delete); do
                last_space_id=$(yabai -m query --spaces | jq '.[-1].index')
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
        ctrl + alt - h : yabai -m window --resize left:-50:0 || yabai -m window --resize right:-50:0
        ctrl + alt - j : yabai -m window --resize bottom:0:50
        ctrl + alt - k : yabai -m window --resize top:0:-50 || yabai -m window --resize bottom:0:-50
        ctrl + alt - l : yabai -m window --resize right:50:0

        # Switch to specific space
        alt - 1 : yabai -m space --focus 1 || yabai -m space --focus recent
        alt - 2 : yabai -m space --focus 2 || yabai -m space --focus recent
        alt - 3 : yabai -m space --focus 3 || yabai -m space --focus recent
        alt - 4 : yabai -m space --focus 4 || yabai -m space --focus recent
        alt - 5 : yabai -m space --focus 5 || yabai -m space --focus recent
        alt - 6 : yabai -m space --focus 6 || yabai -m space --focus recent
        alt - 7 : yabai -m space --focus 7 || yabai -m space --focus recent
        alt - 8 : yabai -m space --focus 8 || yabai -m space --focus recent
        alt - 9 : yabai -m space --focus $(yabai -m query --spaces | jq '.[-1].index')

        # Move window to specific space
        alt + shift - 1 : yabai -m window --space 1
        alt + shift - 2 : yabai -m window --space 2
        alt + shift - 3 : yabai -m window --space 3
        alt + shift - 4 : yabai -m window --space 4
        alt + shift - 5 : yabai -m window --space 5
        alt + shift - 6 : yabai -m window --space 6
        alt + shift - 7 : yabai -m window --space 7
        alt + shift - 8 : yabai -m window --space 8
        alt + shift - 9 : yabai -m window --space $(yabai -m query --spaces | jq '.[-1].index')

        # Toggle Floating Window
        alt - 0 : yabai -m window --toggle float

        # Change between tiled and stacked layout for space
        alt - comma : yabai -m space --layout bsp
        alt - slash : yabai -m space --layout stack
      '';
    };
  };
};
