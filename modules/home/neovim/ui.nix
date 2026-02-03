{pkgs, ...}: {
  programs.nvf.settings.vim = {
    mini.icons = {
      enable = true;
      setupOpts = {
        file = {
          ".keep" = {
            glyph = "󰊢";
            hl = "MiniIconsGrey";
          };
          "devcontainer.json" = {
            glyph = "";
            hl = "MiniIconsAzure";
          };
        };
        filetype = {
          dotenv = {
            glyph = "";
            hl = "MiniIconsYellow";
          };
        };
      };
    };
    luaConfigRC.mini-icons-init = ''
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    '';

    ui.noice = {
      enable = true;
      setupOpts = {
        lsp.override = {
          "vim.lsp.util.convert_input_to_markdown_lines" = true;
          "vim.lsp.util.stylize_markdown" = true;
          "cmp.entry.get_documentation" = true;
        };
        routes = [
          {
            filter = {
              event = "msg_show";
              any = [
                {find = "%d+L, %d+B";}
                {find = "; after #%d+";}
                {find = "; before #%d+";}
              ];
            };
            view = "mini";
          }
        ];
        presets = {
          bottom_search = true;
          command_palette = true;
          long_message_to_split = true;
        };
      };
    };

    luaConfigRC.noice-hack = ''
      if vim.o.filetype == "lazy" then
        vim.cmd([[messages clear]])
      end
    '';

    statusline.lualine = {
      enable = true;
      theme = "auto";
      globalStatus = true;
      disabledFiletypes = ["dashboard" "alpha" "ministarter" "snacks_dashboard"];

      sectionSeparator = {
        left = "";
        right = "";
      };
      componentSeparator = {
        left = "";
        right = "";
      };

      activeSection = {
        a = [''{ "mode", fmt = string.lower }''];
        b = ["'branch'"];
        c = [
          ''function() return vim.fn.fnamemodify(vim.fn.getcwd(), ':t') end''
          ''{ "diagnostics", symbols = { error = " ", warn = " ", info = " ", hint = " " } }''
          ''{ "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } }''
          ''function() return vim.fn.expand("%:p:~:.") end''
          ''{ function() return package.loaded['trouble'] and require('trouble').statusline({mode = 'symbols', groups = {}, title = false, filter = { range = true }, format = '{kind_icon}{symbol.name:Normal}', hl_group = 'lualine_c_normal'}).get() or "" end, cond = function() return package.loaded['trouble'] and require('trouble').statusline({mode = 'symbols', groups = {}, title = false, filter = { range = true }, format = '{kind_icon}{symbol.name:Normal}', hl_group = 'lualine_c_normal'}).has() end }''
        ];
        x = [
          ''function() return package.loaded['snacks'] and require('snacks').profiler.status() or "" end''
          ''{ function() return package.loaded['noice'] and require('noice').api.status.command.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.command.has() end, color = { fg = "#bb9af7" } }''
          ''{ function() return package.loaded['noice'] and require('noice').api.status.mode.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.mode.has() end, color = { fg = "#ff9e64" } }''
          ''{ function() return "  " .. (package.loaded['dap'] and require("dap").status() or "") end, cond = function() return package.loaded['dap'] and require("dap").status() ~= "" end, color = { fg = "#db4b4b" } }''
          ''{ function() return require("lazy.status").updates() end, cond = require("lazy.status").has_updates, color = { fg = "#ff9e64" } }''
          ''{ "diff", symbols = { added = " ", modified = " ", removed = " " }, source = function() local gitsigns = vim.b.gitsigns_status_dict if gitsigns then return { added = gitsigns.added, modified = gitsigns.changed, removed = gitsigns.removed } end end }''
        ];
        y = ["'progress'"];
        z = ["'location'"];
      };

      setupOpts = {
        extensions = ["neo-tree" "lazy" "fzf"];
      };
    };

    keymaps = [
      {
        key = "<leader>snl";
        mode = "n";
        lua = true;
        action = "function() require('noice').cmd('last') end";
        options = {desc = "Noice Last Message";};
      }
      {
        key = "<leader>snh";
        mode = "n";
        lua = true;
        action = "function() require('noice').cmd('history') end";
        options = {desc = "Noice History";};
      }
      {
        key = "<leader>sna";
        mode = "n";
        lua = true;
        action = "function() require('noice').cmd('all') end";
        options = {desc = "Noice All";};
      }
      {
        key = "<leader>snd";
        mode = "n";
        lua = true;
        action = "function() require('noice').cmd('dismiss') end";
        options = {desc = "Dismiss All";};
      }
      {
        key = "<leader>snt";
        mode = "n";
        lua = true;
        action = "function() require('noice').cmd('pick') end";
        options = {desc = "Noice Picker (Telescope/FzfLua)";};
      }
      {
        key = "<c-f>";
        mode = ["i" "n" "s"];
        lua = true;
        action = "function() if not require('noice.lsp').scroll(4) then return '<c-f>' end end";
        options = {
          silent = true;
          expr = true;
          desc = "Scroll Forward";
        };
      }
      {
        key = "<c-b>";
        mode = ["i" "n" "s"];
        lua = true;
        action = "function() if not require('noice.lsp').scroll(-4) then return '<c-b>' end end";
        options = {
          silent = true;
          expr = true;
          desc = "Scroll Backward";
        };
      }
      {
        key = "<S-Enter>";
        mode = "c";
        lua = true;
        action = "function() require('noice').redirect(vim.fn.getcmdline()) end";
        options = {desc = "Redirect Cmdline";};
      }
    ];

    lazy.plugins = {
      "nui.nvim" = {
        package = pkgs.vimPlugins.nui-nvim;
        lazy = true;
      };
    };
  };
}
