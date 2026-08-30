{pkgs, ...}: let
  ctrlOrSuper =
    if pkgs.stdenv.hostPlatform.isDarwin
    then {control = true;}
    else {meta = true;};
  inspectorId =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "key_inspectorMac"
    else "key_inspector";
in {
  programs.zen-browser.profiles."default" = {
    keyboardShortcutsVersion = 19;
    keyboardShortcuts = [
      {
        id = "key_selectTab1";
        key = "1";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab2";
        key = "2";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab3";
        key = "3";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab4";
        key = "4";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab5";
        key = "5";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab6";
        key = "6";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab7";
        key = "7";
        modifiers.accel = true;
      }
      {
        id = "key_selectTab8";
        key = "8";
        modifiers.accel = true;
      }
      {
        id = "key_selectLastTab";
        key = "9";
        modifiers.accel = true;
      }
      {
        id = "zen-copy-url";
        key = "c";
        modifiers = {
          accel = true;
          shift = true;
        };
      }
      {
        id = "zen-copy-url-markdown";
        key = "c";
        modifiers = {
          accel = true;
          alt = true;
          shift = true;
        };
      }
      {
        id = "key_toggleToolbox";
        key = "i";
        modifiers = {
          accel = true;
          alt = true;
        };
      }
      {
        id = inspectorId;
        key = "c";
        modifiers = {
          accel = true;
          alt = true;
        };
      }
      {
        id = "zen-workspace-switch-1";
        key = "1";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-2";
        key = "2";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-3";
        key = "3";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-4";
        key = "4";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-5";
        key = "5";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-6";
        key = "6";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-7";
        key = "7";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-8";
        key = "8";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-9";
        key = "9";
        modifiers = ctrlOrSuper;
      }
      {
        id = "zen-workspace-switch-10";
        key = "0";
        modifiers = ctrlOrSuper;
      }
    ];
  };
}
