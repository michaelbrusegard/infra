{ pkgs, ... }:

{
  services.yabai = {
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
      ${pkgs.yabai}/bin/yabai -m signal --add event=dock_did_restart action="sudo ${pkgs.yabai}/bin/yabai --load-sa"
      sudo ${pkgs.yabai}/bin/yabai --load-sa

      # Space layout settings
      ${pkgs.yabai}/bin/yabai -m config --space 3 layout stack
      ${pkgs.yabai}/bin/yabai -m config --space 6 layout stack
      ${pkgs.yabai}/bin/yabai -m config --space 9 layout float

      # Application rules
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Calculator|System Settings|Archive Utility)$" manage=off
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Brave)$" space=2
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Proton Mail|Proton Pass)$" space=3
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Notes|Obsidian|LibreOffice|Notion)$" space=4
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Messages|FaceTime|Element|Legcord|Slack)$" space=5
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Affinity|Inkscape|Gimp|Scribus|DaVinci Resolve|FreeCAD|OrcaSlicer)$" space=6
      ${pkgs.yabai}/bin/yabai -m rule --add app="^(Music|Photos)$" space=7

      # Make sure there are 9 spaces
      current_spaces=$(${pkgs.yabai}/bin/yabai -m query --spaces | ${pkgs.jq}/bin/jq length)
      spaces_to_create=$((9 - current_spaces))
      spaces_to_delete=$((current_spaces - 9))

      if [[ $spaces_to_create -gt 0 ]]; then
          for i in $(seq 1 $spaces_to_create); do
              ${pkgs.yabai}/bin/yabai -m space --create
          done
      fi

      if [[ $spaces_to_delete -gt 0 ]]; then
          for i in $(seq 1 $spaces_to_delete); do
              last_space_id=$(${pkgs.yabai}/bin/yabai -m query --spaces | ${pkgs.jq}/bin/jq '.[-1].index')
              ${pkgs.yabai}/bin/yabai -m space --destroy $last_space_id
          done
      fi

      # Add signals to refresh the yabai indicator
      ${pkgs.yabai}/bin/yabai -m signal --add event=mission_control_exit action='echo "refresh" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=display_added action='echo "refresh" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=display_removed action='echo "refresh" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_created action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_destroyed action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_focused action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_moved action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_resized action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_minimized action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
      ${pkgs.yabai}/bin/yabai -m signal --add event=window_deminimized action='echo "refresh windows" | nc -U /tmp/yabai-indicator.socket'
    '';
  };

  services.skhd = {
    enable = true;
    skhdConfig = ''
      # Focus window
      alt - h : ${pkgs.yabai}/bin/yabai -m window --focus west || ${pkgs.yabai}/bin/yabai -m display --focus west
      alt - l : ${pkgs.yabai}/bin/yabai -m window --focus east || ${pkgs.yabai}/bin/yabai -m display --focus east
      alt - j : ${pkgs.yabai}/bin/yabai -m window --focus stack.next || ${pkgs.yabai}/bin/yabai -m window --focus south
      alt - k : ${pkgs.yabai}/bin/yabai -m window --focus stack.prev || ${pkgs.yabai}/bin/yabai -m window --focus north

      # Move window
      alt + shift - h : ${pkgs.yabai}/bin/yabai -m window --swap west || ${pkgs.yabai}/bin/yabai -m window --display west
      alt + shift - l : ${pkgs.yabai}/bin/yabai -m window --swap east || ${pkgs.yabai}/bin/yabai -m window --display east
      alt + shift - j : ${pkgs.yabai}/bin/yabai -m window --swap south
      alt + shift - k : ${pkgs.yabai}/bin/yabai -m window --swap north

      # Resize window
      alt - left : ${pkgs.yabai}/bin/yabai -m window --resize left:-20:0 || ${pkgs.yabai}/bin/yabai -m window --resize right:-20:0
      alt - down : ${pkgs.yabai}/bin/yabai -m window --resize bottom:0:20 || ${pkgs.yabai}/bin/yabai -m window --resize top:0:20
      alt - up : ${pkgs.yabai}/bin/yabai -m window --resize top:0:-20 || ${pkgs.yabai}/bin/yabai -m window --resize bottom:0:-20
      alt - right : ${pkgs.yabai}/bin/yabai -m window --resize right:20:0 || ${pkgs.yabai}/bin/yabai -m window --resize left:20:0

      # Switch to specific space
      alt - 1 : ${pkgs.yabai}/bin/yabai -m space --focus 1 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 2 : ${pkgs.yabai}/bin/yabai -m space --focus 2 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 3 : ${pkgs.yabai}/bin/yabai -m space --focus 3 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 4 : ${pkgs.yabai}/bin/yabai -m space --focus 4 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 5 : ${pkgs.yabai}/bin/yabai -m space --focus 5 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 6 : ${pkgs.yabai}/bin/yabai -m space --focus 6 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 7 : ${pkgs.yabai}/bin/yabai -m space --focus 7 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 8 : ${pkgs.yabai}/bin/yabai -m space --focus 8 || ${pkgs.yabai}/bin/yabai -m space --focus recent
      alt - 9 : ${pkgs.yabai}/bin/yabai -m space --focus $(${pkgs.yabai}/bin/yabai -m query --spaces | ${pkgs.jq}/bin/jq '.[-1].index')

      # Move window to specific space
      alt + shift - 1 : ${pkgs.yabai}/bin/yabai -m window --space 1 && ${pkgs.yabai}/bin/yabai -m space --focus 1
      alt + shift - 2 : ${pkgs.yabai}/bin/yabai -m window --space 2 && ${pkgs.yabai}/bin/yabai -m space --focus 2
      alt + shift - 3 : ${pkgs.yabai}/bin/yabai -m window --space 3 && ${pkgs.yabai}/bin/yabai -m space --focus 3
      alt + shift - 4 : ${pkgs.yabai}/bin/yabai -m window --space 4 && ${pkgs.yabai}/bin/yabai -m space --focus 4
      alt + shift - 5 : ${pkgs.yabai}/bin/yabai -m window --space 5 && ${pkgs.yabai}/bin/yabai -m space --focus 5
      alt + shift - 6 : ${pkgs.yabai}/bin/yabai -m window --space 6 && ${pkgs.yabai}/bin/yabai -m space --focus 6
      alt + shift - 7 : ${pkgs.yabai}/bin/yabai -m window --space 7 && ${pkgs.yabai}/bin/yabai -m space --focus 7
      alt + shift - 8 : ${pkgs.yabai}/bin/yabai -m window --space 8 && ${pkgs.yabai}/bin/yabai -m space --focus 8
      alt + shift - 9 : LAST_SPACE=$(${pkgs.yabai}/bin/yabai -m query --spaces | ${pkgs.jq}/bin/jq '.[-1].index'); ${pkgs.yabai}/bin/yabai -m window --space $LAST_SPACE && ${pkgs.yabai}/bin/yabai -m space --focus $LAST_SPACE

      # Toggle Floating Window
      alt - 0 : ${pkgs.yabai}/bin/yabai -m window --toggle float

      # System
      alt - return : open -na "WezTerm" --args start --always-new-process
      alt + shift - return : open -na "WezTerm" --args start --always-new-process -e sh -c 'yazi'
    '';
  };

  services.jankyborders = {
    enable = true;
    hidpi = true;
    style = "round";
    active_color = "0xff89b4fa";
    inactive_color = "0xff45475a";
    width = 4.0;
  };

  system.activationScripts.yabai.text = ''
    echo "Loading yabai scripting addition..."
    ${pkgs.yabai}/bin/yabai --load-sa
  '';
}
