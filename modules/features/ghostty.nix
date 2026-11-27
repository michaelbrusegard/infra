{
  flake.modules.homeManager.ghostty =
    { lib, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
    in
    {
      programs.ghostty = {
        enable = true;
        package = if isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
        # The macOS release bundle ships no bat syntax.
        installBatSyntax = isLinux;
        clearDefaultKeybinds = true;
        settings = {
          font-family = "GeistMono Nerd Font";
          font-size = 15;
          font-feature = [
            "-calt"
            "-liga"
            "-dlig"
          ];
          window-padding-x = 0;
          window-padding-y = 0;

          # Super is Cmd on macOS, and the remap below puts it on the Cmd key on
          # Linux, so one set of bindings serves both.
          keybind = [
            "super+c=copy_to_clipboard"
            "super+v=paste_from_clipboard"
            "super+equal=increase_font_size:1"
            "super+minus=decrease_font_size:1"
            "super+0=reset_font_size"
            "super+q=quit"
            "super+n=new_window"
            "super+t=new_tab"
            "super+w=close_surface"
            "super+shift+w=close_tab"
            "super+backslash=new_split:down"
            "super+shift+backslash=new_split:right"
            "super+h=goto_split:left"
            "super+j=goto_split:down"
            "super+k=goto_split:up"
            "super+l=goto_split:right"
            "super+left=resize_split:left,20"
            "super+down=resize_split:down,20"
            "super+up=resize_split:up,20"
            "super+right=resize_split:right,20"
            "super+z=toggle_split_zoom"
            "ctrl+tab=next_tab"
            "ctrl+shift+tab=previous_tab"
            "super+shift+bracket_left=previous_tab"
            "super+shift+bracket_right=next_tab"
            "super+shift+p=move_tab:-1"
            "super+shift+n=move_tab:1"
          ]
          ++ map (n: "super+${toString n}=goto_tab:${toString n}") (lib.range 1 8)
          ++ [
            "super+9=last_tab"
            "super+f=start_search"
            "super+r=reload_config"
          ];
        }
        // lib.optionalAttrs isLinux {
          window-decoration = "none";
          # Kanata sends Ctrl from the Cmd key and Super from the Control key.
          # Swapping them back gives the shell a real Ctrl from Control, as on
          # macOS. Remaps do not chain, so the pair is a swap.
          key-remap = [
            "ctrl=super"
            "super=ctrl"
          ];
        }
        // lib.optionalAttrs isDarwin {
          macos-titlebar-style = "hidden";
          quit-after-last-window-closed = true;
        };
      };

      home.sessionVariables.TERMINAL = "ghostty";

      xdg.terminal-exec = lib.mkIf isLinux {
        enable = true;
        settings.default = [ "com.mitchellh.ghostty.desktop" ];
      };
    };
}
