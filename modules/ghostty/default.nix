{ config, lib, ... }:

let
  cfg = config.modules.ghostty;
in {
  options.modules.ghostty.enable = lib.mkEnableOption "Ghostty configuration";

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      installBatSyntax = true;
      installVimSyntax = true;
      settings = {
        font-family = "SF Mono Nerd Font";
        font-size = 12.5;
        font-feature = ["-liga" "-dlig" "-calt"];
        unfocused-split-opacity = 0.9;
        window-theme = "dark";
        macos-option-as-alt = true;
        adjust-underline-position = "150%";
        adjust-underline-thickness = 2;
        theme = "catppuccin-mocha";
        mouse-hide-while-typing = true;
        window-padding-x = 0;
        window-padding-y = 0;
        window-decoration = false;
        window-new-tab-position = "end";
        quit-after-last-window-closed = true;
        cursor-style = "block";
        keybind = [
          # Global actions
          "super+c=copy"
          "super+v=paste"
          "super+equal=increase_font_size"
          "super+minus=decrease_font_size"
          "super+0=reset_font_size"
          "super+q=quit"
          "super+n=new_window"
          "super+t=new_tab"
          "shift+super+t=spawn:nvim"

          # Pane actions
          "super+w=close_surface"
          "shift+super+w=close_tab"
          "super+backslash=split_horizontal"
          "shift+super+backslash=split_vertical"

          # Pane navigation
          "super+h=goto_split:left"
          "super+j=goto_split:down"
          "super+k=goto_split:up"
          "super+l=goto_split:right"

          # Resize panes
          "super+s=resize_split:left,2"
          "super+d=resize_split:down,2"
          "super+f=resize_split:up,2"
          "super+g=resize_split:right,2"

          # Tab navigation
          "ctrl+tab=next_tab"
          "shift+ctrl+tab=previous_tab"
          "shift+super+bracketleft=previous_tab"
          "shift+super+bracketright=next_tab"
          "super+1=goto_tab:0"
          "super+2=goto_tab:1"
          "super+3=goto_tab:2"
          "super+4=goto_tab:3"
          "super+5=goto_tab:4"
          "super+6=goto_tab:5"
          "super+7=goto_tab:6"
          "super+8=goto_tab:7"
          "super+9=goto_tab:last"

          # Move tabs
          "shift+super+p=move_tab_backward"
          "shift+super+n=move_tab_forward"

          # Basic actions
          "super+z=toggle_split_zoom"
        ];
      };
    };
  };
}
