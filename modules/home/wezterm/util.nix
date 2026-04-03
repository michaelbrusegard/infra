{pkgs, lib, ...}: {
  programs.wezterm.spec.plugins = {
    "smart_workspace_switcher" = {
      url = "https://github.com/MLFlexer/smart_workspace_switcher.wezterm";
      keys = [
        {
          key = "Enter";
          mods = "SUPER";
          action = ''smart_workspace_switcher.switch_workspace({ extra_args = [[ | grep -E "^$(echo ~/Projects | sed 's:/*$::')/" | awk -F'/' 'NF<=5']] })'';
        }
      ];
      extraLuaAfter = ''
        smart_workspace_switcher.zoxide_path = '${lib.getExe pkgs.zoxide}'

        smart_workspace_switcher.workspace_formatter = function(name)
          return wezterm.format({
            { Foreground = { Color = config.colors.ansi[6] } },
            { Text = wezterm.nerdfonts.cod_terminal_tmux .. ' ' .. string.match(name, '[^/\\\\]+$') },
          })
        end
      '';
    };

    "quick_domains" = {
      url = "https://github.com/DavidRR-F/quick_domains.wezterm";
      configOpts = {
        keys = {
          attach = {
            key = "d";
            mods = "SUPER";
            tbl = "";
          };
          vsplit = {
            key = "F12";
            mods = "SHIFT|CTRL";
            tbl = "";
          };
          hsplit = {
            key = "F12";
            mods = "SHIFT|CTRL";
            tbl = "";
          };
        };
      };
      extraLuaAfter = ''
        quick_domains.formatter = function(icon, title, tab_id, domain_name)
          return wezterm.format({
            { Foreground = { Color = config.colors.ansi[4] } },
            { Text = icon .. ' ' .. title },
          })
        end
      '';
    };
  };
}
