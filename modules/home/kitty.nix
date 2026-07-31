{
  lib,
  pkgs,
  ...
}: let
  terminalMod =
    if pkgs.stdenv.isDarwin
    then "cmd"
    else "ctrl";
  tabMod =
    if pkgs.stdenv.isDarwin
    then "ctrl"
    else "super";

  terminalBindings = {
    "${terminalMod}+c" = "copy_to_clipboard";
    "${terminalMod}+v" = "paste_from_clipboard";
    "${terminalMod}+equal" = "change_font_size all +1.0";
    "${terminalMod}+minus" = "change_font_size all -1.0";
    "${terminalMod}+0" = "change_font_size all 0";
    "${terminalMod}+q" = "quit";
    "${terminalMod}+n" = "new_os_window_with_cwd";
    "${terminalMod}+t" = "new_tab_with_cwd";
    "${terminalMod}+w" = "close_window_with_confirmation ignore-shell";
    "${terminalMod}+shift+w" = "close_tab";
    "${terminalMod}+backslash" = "launch --location=hsplit --cwd=current";
    "${terminalMod}+shift+backslash" = "launch --location=vsplit --cwd=current";
    "${terminalMod}+h" = "neighboring_window left";
    "${terminalMod}+j" = "neighboring_window bottom";
    "${terminalMod}+k" = "neighboring_window top";
    "${terminalMod}+l" = "neighboring_window right";
    "${terminalMod}+left" = "resize_window narrower 2";
    "${terminalMod}+down" = "resize_window taller 2";
    "${terminalMod}+up" = "resize_window shorter 2";
    "${terminalMod}+right" = "resize_window wider 2";
    "${tabMod}+tab" = "next_tab";
    "${tabMod}+shift+tab" = "previous_tab";
    "${terminalMod}+shift+left_bracket" = "previous_tab";
    "${terminalMod}+shift+right_bracket" = "next_tab";
    "${terminalMod}+1" = "goto_tab 1";
    "${terminalMod}+2" = "goto_tab 2";
    "${terminalMod}+3" = "goto_tab 3";
    "${terminalMod}+4" = "goto_tab 4";
    "${terminalMod}+5" = "goto_tab 5";
    "${terminalMod}+6" = "goto_tab 6";
    "${terminalMod}+7" = "goto_tab 7";
    "${terminalMod}+8" = "goto_tab 8";
    "${terminalMod}+9" = "goto_tab -1";
    "${terminalMod}+shift+p" = "move_tab_backward";
    "${terminalMod}+shift+n" = "move_tab_forward";
    "${terminalMod}+f" = "show_scrollback";
    "${terminalMod}+y" = "show_scrollback";
    "${terminalMod}+z" = "toggle_layout stack";
    "${terminalMod}+r" = "load_config_file";
  };

  passthroughKeys =
    lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz0123456789"
    ++ [
      "space"
      "left_bracket"
      "right_bracket"
      "backslash"
      "minus"
      "slash"
      "underscore"
      "^"
      "left"
      "right"
      "up"
      "down"
      "backspace"
      "delete"
      "enter"
    ];
  passthroughBindings = lib.listToAttrs (map (key: {
      name = "super+${key}";
      value = "send_key ctrl+${key}";
    })
    passthroughKeys);
in {
  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
    settings = {
      font_family = "GeistMono Nerd Font";
      font_size = 15;
      disable_ligatures = "always";
      window_padding_width = 0;
      hide_window_decorations = true;
      enabled_layouts = "splits";
      tab_bar_style = "separator";
      tab_title_template = "{index}: {title}";
      active_tab_title_template = "{index}: {title}";
      show_hyperlink_targets = true;
      enable_audio_bell = false;
      clear_all_shortcuts = true;
    };
    keybindings =
      terminalBindings
      // lib.optionalAttrs pkgs.stdenv.isLinux passthroughBindings;
  };

  home.sessionVariables.TERMINAL = "kitty";

  xdg.terminal-exec = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    settings.default = ["kitty.desktop"];
  };
}
