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

    maps.normal = {
      "<leader>snl" = {
        action = "function() require('noice').cmd('last') end";
        lua = true;
        desc = "Noice Last Message";
      };
      "<leader>snh" = {
        action = "function() require('noice').cmd('history') end";
        lua = true;
        desc = "Noice History";
      };
      "<leader>sna" = {
        action = "function() require('noice').cmd('all') end";
        lua = true;
        desc = "Noice All";
      };
      "<leader>snd" = {
        action = "function() require('noice').cmd('dismiss') end";
        lua = true;
        desc = "Dismiss All";
      };
      "<leader>snt" = {
        action = "function() require('noice').cmd('pick') end";
        lua = true;
        desc = "Noice Picker (Telescope/FzfLua)";
      };
      "<c-f>" = {
        action = "function() if not require('noice.lsp').scroll(4) then return '<c-f>' end end";
        lua = true;
        silent = true;
        expr = true;
        desc = "Scroll Forward";
        mode = ["i" "n" "s"];
      };
      "<c-b>" = {
        action = "function() if not require('noice.lsp').scroll(-4) then return '<c-b>' end end";
        lua = true;
        silent = true;
        expr = true;
        desc = "Scroll Backward";
        mode = ["i" "n" "s"];
      };
    };

    maps.command = {
      "<S-Enter>" = {
        action = "function() require('noice').redirect(vim.fn.getcmdline()) end";
        lua = true;
        desc = "Redirect Cmdline";
      };
    };

    statusline.lualine = {
      enable = true;
      theme = "auto";
      globalStatus = true;
      activeSection = {
        a = ["'mode'"];
        b = ["'branch'"];
        c = [
          ''function() return vim.fn.fnamemodify(vim.fn.getcwd(), ':t') end''
          ''{ "diagnostics", symbols = { error = " ", warn = " ", info = " ", hint = " " } }''
          ''{ "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } }''
          ''function() return vim.fn.expand("%:p:~:.") end''
        ];
        x = [
          ''function() return package.loaded['snacks'] and require('snacks').profiler.status() or "" end''
          ''{ function() return package.loaded['noice'] and require('noice').api.status.command.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.command.has() end, color = { fg = "#bb9af7" } }''
          ''{ function() return package.loaded['noice'] and require('noice').api.status.mode.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.mode.has() end, color = { fg = "#ff9e64" } }''
          ''{ function() return "  " .. (package.loaded['dap'] and require("dap").status() or "") end, cond = function() return package.loaded['dap'] and require("dap").status() ~= "" end, color = { fg = "#db4b4b" } }''
          ''{ "diff", symbols = { added = " ", modified = " ", removed = " " }, source = function() local gitsigns = vim.b.gitsigns_status_dict if gitsigns then return { added = gitsigns.added, modified = gitsigns.changed, removed = gitsigns.removed } end end }''
        ];
        y = [
          ''{ "progress", separator = " ", padding = { left = 1, right = 0 } }''
          ''{ "location", padding = { left = 0, right = 1 } }''
        ];
        z = [
          ''function() return " " .. os.date("%R") end''
        ];
      };
    };

    lazy.plugins = {
      "nui.nvim" = {
        package = pkgs.vimPlugins.nui-nvim;
        lazy = true;
      };
    };
  };
}
