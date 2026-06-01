_: {
  programs.zen-browser.profiles."default" = {
    keyboardShortcutsVersion = 19;
    keyboardShortcuts = [
      {
        id = "key_wrToggleCaptureSequenceCmd";
        key = "6";
        modifiers = {
          control = true;
          shift = true;
        };
      }
      {
        id = "key_wrCaptureCmd";
        key = "3";
        modifiers = {
          control = true;
          shift = true;
        };
      }
      {
        id = "key_selectLastTab";
        key = "9";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab8";
        key = "8";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab7";
        key = "7";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab6";
        key = "6";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab5";
        key = "5";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab4";
        key = "4";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab3";
        key = "3";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab2";
        key = "2";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectTab1";
        key = "1";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_undoCloseWindow";
        key = "n";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_restoreLastClosedTabOrWindowOrSession";
        key = "t";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_quitApplication";
        key = "q";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_sanitize";
        keycode = "VK_DELETE";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_screenshot";
        key = "s";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_privatebrowsing";
        key = "p";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_switchTextDirection";
        key = "x";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_showAllTabs";
        keycode = "VK_TAB";
        modifiers = {
          control = true;
          shift = true;
        };
      }
      {
        id = "key_fullZoomReset";
        key = "0";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_fullZoomEnlarge";
        key = "+";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_fullZoomReduce";
        key = "-";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_gotoHistory";
        key = "h";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "toggleSidebarKb";
        key = "z";
        modifiers = {
          control = true;
        };
      }
      {
        id = "viewGenaiChatSidebarKb";
        key = "x";
        modifiers = {
          control = true;
        };
      }
      {
        id = "key_stop";
        keycode = "VK_ESCAPE";
      }
      {
        id = "viewBookmarksToolbarKb";
        key = "b";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "viewBookmarksSidebarKb";
        key = "b";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "manBookmarkKb";
        key = "o";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "bookmarkAllTabsKb";
        key = "d";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "addBookmarkAsKb";
        key = "d";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_findPrevious";
        key = "g";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_findAgain";
        key = "g";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_find";
        key = "f";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_viewInfo";
        key = "i";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_viewSource";
        key = "u";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_aboutProcesses";
        keycode = "VK_ESCAPE";
        modifiers = {
          shift = true;
        };
      }
      {
        id = "key_reload_skip_cache";
        key = "r";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_reload";
        key = "r";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_togglePictureInPicture";
        key = "]";
        modifiers = {
          alt = true;
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_toggleReaderMode";
        key = "r";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_exitFullScreen";
        key = "f";
        modifiers = {
          control = true;
          meta = true;
        };
      }
      {
        id = "key_enterFullScreen";
        key = "f";
        modifiers = {
          control = true;
          meta = true;
        };
      }
      {
        id = "showAllHistoryKb";
        key = "y";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "goHome";
        keycode = "VK_HOME";
        modifiers = {
          alt = true;
        };
      }
      {
        id = "goForwardKb2";
        key = "]";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "goBackKb2";
        key = "[";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "goForwardKb";
        keycode = "VK_RIGHT";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "goBackKb";
        keycode = "VK_LEFT";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_selectAll";
        key = "a";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_delete";
        keycode = "VK_DELETE";
      }
      {
        id = "key_paste";
        key = "v";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_copy";
        key = "c";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_cut";
        key = "x";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_redo";
        key = "z";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_undo";
        key = "z";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_toggleMute";
        key = "m";
        modifiers = {
          control = true;
        };
      }
      {
        id = "key_closeWindow";
        key = "w";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_close";
        key = "w";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "printKb";
        key = "p";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_savePage";
        key = "s";
        modifiers = {
          alt = true;
          shift = true;
          meta = true;
        };
      }
      {
        id = "openFileKb";
        key = "o";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_openAddons";
        key = "a";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_openDownloads";
        key = "j";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_search2";
        key = "f";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_search";
        key = "k";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "focusURLBar";
        key = "l";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_newNavigatorTab";
        key = "t";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "key_newNavigator";
        key = "n";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "zen-compact-mode-toggle";
        key = "s";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "zen-compact-mode-show-sidebar";
        key = "s";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "zen-workspace-switch-10";
        key = "0";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-9";
        key = "9";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-8";
        key = "8";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-7";
        key = "7";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-6";
        key = "6";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-5";
        key = "5";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-4";
        key = "4";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-3";
        key = "3";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-2";
        key = "2";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-switch-1";
        key = "1";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-forward";
        key = "n";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-workspace-backward";
        key = "p";
        modifiers = {
          control = true;
        };
      }
      {
        id = "zen-split-view-grid";
        key = "g";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "zen-split-view-vertical";
        key = "v";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "zen-split-view-horizontal";
        key = "h";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "zen-split-view-unsplit";
        key = "u";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "zen-pinned-tab-reset-shortcut";
        key = "r";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "zen-toggle-sidebar";
        key = "b";
        modifiers = {
          alt = true;
        };
      }
      {
        id = "zen-copy-url";
        key = "c";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "zen-copy-url-markdown";
        key = "c";
        modifiers = {
          alt = true;
          shift = true;
          meta = true;
        };
      }
      {
        id = "zen-toggle-pin-tab";
        key = "d";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "zen-glance-expand";
        key = "o";
        modifiers = {
          meta = true;
        };
      }
      {
        id = "zen-new-empty-split-view";
        key = "*";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "zen-close-all-unpinned-tabs";
        key = "k";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "zen-new-unsynced-window";
        key = "n";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_accessibility";
        keycode = "VK_F12";
        modifiers = {
          shift = true;
        };
      }
      {
        id = "key_dom";
        key = "w";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_storage";
        keycode = "VK_F9";
        modifiers = {
          shift = true;
        };
      }
      {
        id = "key_performance";
        keycode = "VK_F5";
        modifiers = {
          shift = true;
        };
      }
      {
        id = "key_styleeditor";
        keycode = "VK_F7";
        modifiers = {
          shift = true;
        };
      }
      {
        id = "key_netmonitor";
        key = "e";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_jsdebugger";
        key = "z";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_webconsole";
        key = "k";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_inspector";
        key = "L";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_responsiveDesignMode";
        key = "m";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
      {
        id = "key_browserConsole";
        key = "j";
        modifiers = {
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_browserToolbox";
        key = "i";
        modifiers = {
          alt = true;
          shift = true;
          meta = true;
        };
      }
      {
        id = "key_toggleToolbox";
        key = "i";
        modifiers = {
          alt = true;
          meta = true;
        };
      }
    ];
  };
}
