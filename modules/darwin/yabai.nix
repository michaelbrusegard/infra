{
  pkgs,
  lib,
  ...
}: {
  services = {
    yabai = {
      enable = true;
      enableScriptingAddition = true;

      config = {
        layout = "bsp";
        focus_follows_mouse = "off";
        mouse_modifier = "alt";
        top_padding = 6;
        bottom_padding = 6;
        left_padding = 6;
        right_padding = 6;
        window_gap = 6;
        insert_feedback_color = "0xff89b4fa";
      };

      extraConfig = ''
        # Load the scripting-addition into Dock.app
        ${lib.getExe pkgs.yabai} -m signal --add event=dock_did_restart action="sudo ${lib.getExe pkgs.yabai} --load-sa"
        sudo ${lib.getExe pkgs.yabai} --load-sa

        # Space layout settings
        ${lib.getExe pkgs.yabai} -m config --space 3 layout stack
        ${lib.getExe pkgs.yabai} -m config --space 6 layout stack
        ${lib.getExe pkgs.yabai} -m config --space 9 layout float

        # Application rules
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Calculator|System Settings|Archive Utility)$" manage=off
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Zen)$" space=2
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Proton Mail|Proton Pass)$" space=3
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Notes|Obsidian|LibreOffice|Notion)$" space=4
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Messages|FaceTime|Element|Legcord|Slack)$" space=5
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Affinity|Inkscape|Gimp|Scribus|DaVinci Resolve|FreeCAD|OrcaSlicer)$" space=6
        ${lib.getExe pkgs.yabai} -m rule --add app="^(Music|Photos)$" space=7

        # Make sure there are 9 spaces
        current_spaces=$(${lib.getExe pkgs.yabai} -m query --spaces | ${lib.getExe pkgs.jq} length)
        spaces_to_create=$((9 - current_spaces))
        spaces_to_delete=$((current_spaces - 9))

        if [[ $spaces_to_create -gt 0 ]]; then
            for i in $(seq 1 $spaces_to_create); do
                ${lib.getExe pkgs.yabai} -m space --create
            done
        fi

        if [[ $spaces_to_delete -gt 0 ]]; then
            for i in $(seq 1 $spaces_to_delete); do
                last_space_id=$(${lib.getExe pkgs.yabai} -m query --spaces | ${lib.getExe pkgs.jq} '.[-1].index')
                ${lib.getExe pkgs.yabai} -m space --destroy $last_space_id
            done
        fi

        # Add signals to refresh the yabai indicator
        ${lib.getExe pkgs.yabai} -m signal --add event=mission_control_exit action='echo "refresh" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=display_added action='echo "refresh" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=display_removed action='echo "refresh" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_created action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_destroyed action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_focused action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_moved action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_resized action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_minimized action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
        ${lib.getExe pkgs.yabai} -m signal --add event=window_deminimized action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      '';
    };

    skhd = {
      enable = true;
      skhdConfig = ''
        # Focus window
        alt - h : ${lib.getExe pkgs.yabai} -m window --focus west || ${lib.getExe pkgs.yabai} -m display --focus west
        alt - l : ${lib.getExe pkgs.yabai} -m window --focus east || ${lib.getExe pkgs.yabai} -m display --focus east
        alt - j : ${lib.getExe pkgs.yabai} -m window --focus stack.next || ${lib.getExe pkgs.yabai} -m window --focus south
        alt - k : ${lib.getExe pkgs.yabai} -m window --focus stack.prev || ${lib.getExe pkgs.yabai} -m window --focus north

        # Move window
        alt + shift - h : ${lib.getExe pkgs.yabai} -m window --swap west || ${lib.getExe pkgs.yabai} -m window --display west
        alt + shift - l : ${lib.getExe pkgs.yabai} -m window --swap east || ${lib.getExe pkgs.yabai} -m window --display east
        alt + shift - j : ${lib.getExe pkgs.yabai} -m window --swap south
        alt + shift - k : ${lib.getExe pkgs.yabai} -m window --swap north

        # Resize window
        alt - left : ${lib.getExe pkgs.yabai} -m window --resize left:-20:0 || ${lib.getExe pkgs.yabai} -m window --resize right:-20:0
        alt - down : ${lib.getExe pkgs.yabai} -m window --resize bottom:0:20 || ${lib.getExe pkgs.yabai} -m window --resize top:0:20
        alt - up : ${lib.getExe pkgs.yabai} -m window --resize top:0:-20 || ${lib.getExe pkgs.yabai} -m window --resize bottom:0:-20
        alt - right : ${lib.getExe pkgs.yabai} -m window --resize right:20:0 || ${lib.getExe pkgs.yabai} -m window --resize left:20:0

        # Switch to specific space
        alt - 1 : ${lib.getExe pkgs.yabai} -m space --focus 1 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 2 : ${lib.getExe pkgs.yabai} -m space --focus 2 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 3 : ${lib.getExe pkgs.yabai} -m space --focus 3 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 4 : ${lib.getExe pkgs.yabai} -m space --focus 4 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 5 : ${lib.getExe pkgs.yabai} -m space --focus 5 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 6 : ${lib.getExe pkgs.yabai} -m space --focus 6 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 7 : ${lib.getExe pkgs.yabai} -m space --focus 7 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 8 : ${lib.getExe pkgs.yabai} -m space --focus 8 || ${lib.getExe pkgs.yabai} -m space --focus recent
        alt - 9 : ${lib.getExe pkgs.yabai} -m space --focus $(${lib.getExe pkgs.yabai} -m query --spaces | ${lib.getExe pkgs.jq} '.[-1].index')

        # Move window to specific space
        alt + shift - 1 : ${lib.getExe pkgs.yabai} -m window --space 1 && ${lib.getExe pkgs.yabai} -m space --focus 1
        alt + shift - 2 : ${lib.getExe pkgs.yabai} -m window --space 2 && ${lib.getExe pkgs.yabai} -m space --focus 2
        alt + shift - 3 : ${lib.getExe pkgs.yabai} -m window --space 3 && ${lib.getExe pkgs.yabai} -m space --focus 3
        alt + shift - 4 : ${lib.getExe pkgs.yabai} -m window --space 4 && ${lib.getExe pkgs.yabai} -m space --focus 4
        alt + shift - 5 : ${lib.getExe pkgs.yabai} -m window --space 5 && ${lib.getExe pkgs.yabai} -m space --focus 5
        alt + shift - 6 : ${lib.getExe pkgs.yabai} -m window --space 6 && ${lib.getExe pkgs.yabai} -m space --focus 6
        alt + shift - 7 : ${lib.getExe pkgs.yabai} -m window --space 7 && ${lib.getExe pkgs.yabai} -m space --focus 7
        alt + shift - 8 : ${lib.getExe pkgs.yabai} -m window --space 8 && ${lib.getExe pkgs.yabai} -m space --focus 8
        alt + shift - 9 : LAST_SPACE=$(${lib.getExe pkgs.yabai} -m query --spaces | ${lib.getExe pkgs.jq} '.[-1].index'); ${lib.getExe pkgs.yabai} -m window --space $LAST_SPACE && ${lib.getExe pkgs.yabai} -m space --focus $LAST_SPACE

        # Toggle Floating Window
        alt - 0 : ${lib.getExe pkgs.yabai} -m window --toggle float

        # System
        alt - return : open -na "WezTerm" --args start --always-new-process
        alt + shift - return : open -na "WezTerm" --args start --always-new-process -e sh -c 'yazi'
      '';
    };

    jankyborders = {
      enable = true;
      hidpi = true;
      style = "round";
      active_color = "0xff89b4fa";
      inactive_color = "0xff45475a";
      width = 4.0;
    };
  };

  system.activationScripts.yabai.text = ''
    echo "Loading yabai scripting addition..."
    ${lib.getExe pkgs.yabai} --load-sa
  '';
}
