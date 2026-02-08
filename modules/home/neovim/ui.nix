{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec.plugins = {
    "mini-icons" = {
      package = pkgs.vimPlugins.mini-icons;
      event = ["UIEnter"];
      setupModule = "mini.icons";
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
      extraLuaBefore = ''
        package.preload["nvim-web-devicons"] = function()
          require("mini.icons").mock_nvim_web_devicons()
          return package.loaded["nvim-web-devicons"]
        end
      '';
    };

    "noice" = {
      package = pkgs.vimPlugins.noice-nvim;
      event = ["UIEnter"];
      setupModule = "noice";
      setupOpts = {
        notify = {enabled = false;};
        lsp = {
          override = {
            "vim.lsp.util.convert_input_to_markdown_lines" = true;
            "vim.lsp.util.stylize_markdown" = true;
            "cmp.entry.get_documentation" = true;
          };
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
      keymaps = [
        {
          key = "<leader>sn";
          mode = "n";
          desc = "+noice";
          action = "function() end";
          lua = true;
        }
        {
          key = "<S-Enter>";
          mode = "c";
          desc = "Redirect Cmdline";
          action = "function() require('noice').redirect(vim.fn.getcmdline()) end";
          lua = true;
        }
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
          desc = "Noice Picker";
          action = "function() require('noice').cmd('pick') end";
          lua = true;
        }
        {
          key = "<c-f>";
          mode = ["i" "n" "s"];
          desc = "Scroll Forward";
          action = "function() if not require('noice.lsp').scroll(4) then return '<c-f>' end end";
          lua = true;
          expr = true;
          silent = true;
        }
        {
          key = "<c-b>";
          mode = ["i" "n" "s"];
          desc = "Scroll Backward";
          action = "function() if not require('noice.lsp').scroll(-4) then return '<c-b>' end end";
          lua = true;
          expr = true;
          silent = true;
        }
      ];
    };

    "lualine" = {
      package = pkgs.vimPlugins.lualine-nvim;
      event = ["UIEnter"];
      setupModule = "lualine";
      extraLuaBefore = ''
        local function pretty_path(opts)
          opts = vim.tbl_extend("force", {
            relative = "cwd",
            modified_hl = "MatchParen",
            directory_hl = "Conceal",
            filename_hl = "Bold",
            modified_sign = "",
            readonly_icon = " 󰌾 ",
            length = 3,
          }, opts or {})
          return function(self)
            local path = vim.fn.expand("%:p")
            if path == "" then
              return ""
            end
            local cwd = vim.fn.getcwd()
            local root = vim.fn.fnamemodify(cwd, ":t")
            local sep = package.config:sub(1, 1)
            if opts.relative == "cwd" and path:find(cwd, 1, true) == 1 then
              path = path:sub(#cwd + 2)
            end
            local parts = vim.split(path, "[\\/]")
            if opts.length == 0 then
              parts = parts
            elseif #parts > opts.length then
              parts = { parts[1], "…", unpack(parts, #parts - opts.length + 2, #parts) }
            end
            local filename = parts[#parts]
            if opts.modified_hl and vim.bo.modified then
              filename = filename .. opts.modified_sign
            end
            local dir = ""
            if #parts > 1 then
              dir = table.concat({ unpack(parts, 1, #parts - 1) }, sep)
              dir = dir .. sep
            end
            local readonly = ""
            if vim.bo.readonly then
              readonly = opts.readonly_icon
            end
            return dir .. filename .. readonly
          end
        end
      '';
      setupOpts = {
        options = {
          theme = "auto";
          globalstatus = true;
          section_separators = {
            left = "";
            right = "";
          };
          component_separators = {
            left = "";
            right = "";
          };
        };
        sections = {
          lualine_a = [(lib.generators.mkLuaInline ''{ "mode", fmt = string.lower }'')];
          lualine_b = ["branch"];
          lualine_c = [
            (lib.generators.mkLuaInline ''{ function() return vim.fn.fnamemodify(vim.fn.getcwd(), ':t') end, color = { gui = "bold" } }'')
            (lib.generators.mkLuaInline ''{ "diagnostics", symbols = { error = " ", warn = " ", info = " ", hint = " " } }'')
            (lib.generators.mkLuaInline ''{ "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } }'')
            (lib.generators.mkLuaInline ''{ pretty_path(), color = { gui = "bold" } }'')
            (lib.generators.mkLuaInline ''{ "navic", color_correction = "dynamic" }'')
            (lib.generators.mkLuaInline ''{ function() return package.loaded['trouble'] and require('trouble').statusline({mode = 'symbols', groups = {}, title = false, filter = { range = true }, format = '{kind_icon}{symbol.name:Normal}', hl_group = 'lualine_c_normal'}).get() or "" end, cond = function() return package.loaded['trouble'] and require('trouble').statusline({mode = 'symbols', groups = {}, title = false, filter = { range = true }, format = '{kind_icon}{symbol.name:Normal}', hl_group = 'lualine_c_normal'}).has() or false end }'')
          ];
          lualine_x = [
            (lib.generators.mkLuaInline ''package.loaded['snacks'] and require('snacks').profiler.status()'')
            (lib.generators.mkLuaInline ''{ function() return package.loaded['noice'] and require('noice').api.status.command.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.command.has() or false end, color = { fg = "#bb9af7" } }'')
            (lib.generators.mkLuaInline ''{ function() return package.loaded['noice'] and require('noice').api.status.mode.get() or "" end, cond = function() return package.loaded['noice'] and require('noice').api.status.mode.has() or false end, color = { fg = "#ff9e64" } }'')
            (lib.generators.mkLuaInline ''{ require("opencode").statusline }'')
            (lib.generators.mkLuaInline ''{ function() return "  " .. (package.loaded['dap'] and require("dap").status() or "") end, cond = function() return package.loaded['dap'] and require("dap").status() ~= "" or false end, color = { fg = "#db4b4b" } }'')
            (lib.generators.mkLuaInline ''{ "diff", symbols = { added = " ", modified = " ", removed = " " }, source = function() local gitsigns = vim.b.gitsigns_status_dict if gitsigns then return { added = gitsigns.added, modified = gitsigns.changed, removed = gitsigns.removed } end return nil end }'')
          ];
          lualine_y = ["progress"];
          lualine_z = ["location"];
        };
      };
    };
  };
}
