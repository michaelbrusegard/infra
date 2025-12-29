{ pkgs, inputs, ... }:

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
      yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
      sudo yabai --load-sa

      yabai -m config --space 3 layout stack
      yabai -m config --space 6 layout stack
      yabai -m config --space 9 layout float

      yabai -m rule --add app="^(Calculator|System Settings|Archive Utility)$" manage=off
      yabai -m rule --add app="^(Vivaldi)$" space=2
      yabai -m rule --add app="^(Proton Mail|Proton Pass)$" space=3
      yabai -m rule --add app="^(Notes|Obsidian|LibreOffice|Notion)$" space=4
      yabai -m rule --add app="^(Messages|FaceTime|Element|Legcord|Slack)$" space=5
      yabai -m rule --add app="^(Affinity|Inkscape|Gimp|Scribus|DaVinci Resolve|FreeCAD|OrcaSlicer)$" space=6
      yabai -m rule --add app="^(Music|Photos)$" space=7
    '';
  };

  services.skhd = {
    enable = true;
    skhdConfig = ''
      alt - h : yabai -m window --focus west || yabai -m display --focus west
      alt - l : yabai -m window --focus east || yabai -m display --focus east
      alt - j : yabai -m window --focus stack.next || yabai -m window --focus south
      alt - k : yabai -m window --focus stack.prev || yabai -m window --focus north
      alt - 0 : yabai -m window --toggle float
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
    ${inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.yabai}/bin/yabai --load-sa
  '';
}
