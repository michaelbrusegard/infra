_: {
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
        notify = {
          enabled = false;
        };
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
          ''{ "navic", color_correction = "dynamic" }''
          ''{ function() return package.loaded['trouble'] and require('trouble').statusline({mode = 'symbols', groups = {}, title = false, filter = { range = true }, format = '{kind_icon}{symbol.name:Normal}', hl_group = 'lualine_c_normal'}).get() or "" end, cond = function() return package.loaded['trouble'] and require('trouble').statusline({mode = 'symbols', groups = {}, title = false, filter = { range = true }, format = '{kind_icon}{symbol.name:Normal}', hl_group = 'lualine_c_normal'}).has() end }''
        ];
        x = [
          ''function() return package.loaded['snacks'] and require('snacks').profiler.status() or "" end''
          ''{ function() return package.loaded['noice'] and require('noice').api.status.command.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.command.has() end, color = { fg = "#bb9af7" } }''
          ''{ function() return package.loaded['noice'] and require('noice').api.status.mode.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.mode.has() end, color = { fg = "#ff9e64" } }''
          ''{ function() return "  " .. (package.loaded['dap'] and require("dap").status() or "") end, cond = function() return package.loaded['dap'] and require("dap").status() ~= "" end, color = { fg = "#db4b4b" } }''
          ''{ "diff", symbols = { added = " ", modified = " ", removed = " " }, source = function() local gitsigns = vim.b.gitsigns_status_dict if gitsigns then return { added = gitsigns.added, modified = gitsigns.changed, removed = gitsigns.removed } end end }''
        ];
        y = ["'progress'"];
        z = ["'location'"];
      };
    };

    keymaps = [
      {
        key = "<leader>snl";
        mode = "n";
        desc = "Noice Last Message";
        action = "function() require('noice').cmd('last') end";
        lua = true;
      }
      {
        key = "<leader>snh";
        mode = "n";
        desc = "Noice History";
        action = "function() require('noice').cmd('history') end";
        lua = true;
      }
      {
        key = "<leader>sna";
        mode = "n";
        desc = "Noice All";
        action = "function() require('noice').cmd('all') end";
        lua = true;
      }
      {
        key = "<leader>snd";
        mode = "n";
        desc = "Dismiss All";
        action = "function() require('noice').cmd('dismiss') end";
        lua = true;
      }
      {
        key = "<leader>snt";
        mode = "n";
        desc = "Noice Picker (Telescope/FzfLua)";
        action = "function() require('noice').cmd('pick') end";
        lua = true;
      }
      {
        key = "<c-f>";
        mode = ["i" "n" "s"];
        desc = "Scroll Forward";
        action = "function() if not require('noice.lsp').scroll(4) then return '<c-f>' end end";
        lua = true;
      }
      {
        key = "<c-b>";
        mode = ["i" "n" "s"];
        desc = "Scroll Backward";
        action = "function() if not require('noice.lsp').scroll(-4) then return '<c-b>' end end";
        lua = true;
      }
      {
        key = "<S-Enter>";
        mode = "c";
        desc = "Redirect Cmdline";
        action = "function() require('noice').redirect(vim.fn.getcmdline()) end";
        lua = true;
      }
    ];
  };
}
