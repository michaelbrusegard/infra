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
          "super+c=copy_to_clipboard"
          "super+v=paste_from_clipboard"
          "super+equal=increase_font_size"
          "super+minus=decrease_font_size"
          "super+zero=reset_font_size"
          "super+q=quit"
          "super+n=new_window"
          "super+t=new_tab"
          "shift+super+t=spawn:nvim"

          # Pane actions
          "super+w=close_surface"
          "shift+super+w=close_tab"
          "super+backslash=new_split:down"
          "shift+super+backslash=new_split:right"

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
          "shift+super+left_bracket=previous_tab"
          "shift+super+right_bracket=next_tab"
          "super+one=goto_tab:0"
          "super+two=goto_tab:1"
          "super+three=goto_tab:2"
          "super+four=goto_tab:3"
          "super+five=goto_tab:4"
          "super+six=goto_tab:5"
          "super+seven=goto_tab:6"
          "super+eight=goto_tab:7"
          "super+nine=goto_tab:last"

          # Move tabs
          "shift+super+p=move_tab:-1"
          "shift+super+n=move_tab:1"

          # Basic actions
          "super+z=toggle_split_zoom"
        ];
      };
    };
  };
}
