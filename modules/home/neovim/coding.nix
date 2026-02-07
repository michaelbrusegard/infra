{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim.lazy.plugins = {
    "ts-comments.nvim" = {
      package = pkgs.vimPlugins.ts-comments-nvim;
      setupModule = "ts-comments";
      event = [
        {
          event = "User";
          pattern = "LazyFile";
        }
      ];
    };

    "mini.pairs" = {
      package = pkgs.vimPlugins.mini-pairs;
      setupModule = "mini.pairs";
      event = ["InsertEnter"];
      setupOpts = {
        modes = {
          insert = true;
          command = true;
          terminal = false;
        };
        skip_next = ''[%w%%%'%[%%"%.%%`%%$]'';
        skip_ts = ["string"];
        skip_unbalanced = true;
        markdown = true;
      };
      after = ''
        local pairs = require("mini.pairs")
        local open = pairs.open
        pairs.open = function(pair, neigh_pattern)
          if vim.fn.getcmdline() ~= "" then
            return open(pair, neigh_pattern)
          end
          local o, c = pair:sub(1, 1), pair:sub(2, 2)
          local line = vim.api.nvim_get_current_line()
          local cursor = vim.api.nvim_win_get_cursor(0)
          local next = line:sub(cursor[2] + 1, cursor[2] + 1)
          local before = line:sub(1, cursor[2])
          if vim.bo.filetype == "markdown" and o == "`" and before:match("^%s*``") then
            return "`\n```" .. vim.api.nvim_replace_termcodes("<up>", true, true, true)
          end
          if next ~= "" and next:match("[%w%%%'%[%%\"%.%%`%%$]") then
            return o
          end
          local ok, captures = pcall(vim.treesitter.get_captures_at_pos, 0, cursor[1] - 1, math.max(cursor[2] - 1, 0))
          for _, capture in ipairs(ok and captures or {}) do
            if vim.tbl_contains({ "string" }, capture.capture) then
              return o
            end
          end
          if next == c and c ~= o then
            local _, count_open = line:gsub(vim.pesc(pair:sub(1, 1)), "")
            local _, count_close = line:gsub(vim.pesc(pair:sub(2, 2)), "")
            if count_close > count_open then
              return o
            end
          end
          return open(pair, neigh_pattern)
        end
      '';
    };

    "mini.ai" = {
      package = pkgs.vimPlugins.mini-ai;
      setupModule = "mini.ai";
      event = [
        {
          event = "User";
          pattern = "LazyFile";
        }
      ];
      setupOpts = {
        n_lines = 500;
        custom_textobjects = lib.generators.mkLuaInline ''
          {
            o = require("mini.ai").gen_spec.treesitter({
              a = { "@block.outer", "@conditional.outer", "@loop.outer" },
              i = { "@block.inner", "@conditional.inner", "@loop.inner" },
            }),
            f = require("mini.ai").gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
            c = require("mini.ai").gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
            t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%%1>", "^<.->().*()</[^/]->$" },
            d = { "%f[%d]%d+" },
            e = {
              { "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
              "^().*()$",
            },
            g = function(ai_type)
              local start_line, end_line = 1, vim.fn.line('$')
              if ai_type == 'i' then
                local first_nonblank = vim.fn.nextnonblank(start_line)
                local last_nonblank = vim.fn.prevnonblank(end_line)
                if first_nonblank == 0 or last_nonblank == 0 then
                  return nil
                end
                start_line, end_line = first_nonblank, last_nonblank
              end
              local to_col = math.max(vim.fn.getline(end_line):len(), 1)
              return { from = { line = start_line, col = 1 }, to = { line = end_line, col = to_col } }
            end,
            u = require("mini.ai").gen_spec.function_call(),
            U = require("mini.ai").gen_spec.function_call({ name_pattern = "[%w_]" }),
          }
        '';
      };
      after = ''
        local objects = {
          { " ", desc = "whitespace" },
          { '"', desc = "\" string" },
          { "'", desc = "' string" },
          { "(", desc = "() block" },
          { ")", desc = "() block with ws" },
          { "<", desc = "<> block" },
          { ">", desc = "<> block with ws" },
          { "?", desc = "user prompt" },
          { "U", desc = "use/call without dot" },
          { "[", desc = "[] block" },
          { "]", desc = "[] block with ws" },
          { "_", desc = "underscore" },
          { "`", desc = "` string" },
          { "a", desc = "argument" },
          { "b", desc = ")]} block" },
          { "c", desc = "class" },
          { "d", desc = "digit(s)" },
          { "e", desc = "CamelCase / snake_case" },
          { "f", desc = "function" },
          { "g", desc = "entire file" },
          { "i", desc = "indent" },
          { "o", desc = "block, conditional, loop" },
          { "q", desc = "quote" },
          { "t", desc = "tag" },
          { "u", desc = "use/call" },
          { "{", desc = "{} block" },
          { "}", desc = "{} with ws" },
        }

        local ret = { mode = { "o", "x" } }
        local mappings = vim.tbl_extend("force", {}, {
          around = "a",
          inside = "i",
          around_next = "an",
          inside_next = "in",
          around_last = "al",
          inside_last = "il",
        }, require("mini.ai").config.mappings or {})
        mappings.goto_left = nil
        mappings.goto_right = nil

        for name, prefix in pairs(mappings) do
          name = name:gsub("^around_", ""):gsub("^inside_", "")
          ret[#ret + 1] = { prefix, group = name }
          for _, obj in ipairs(objects) do
            local desc = obj.desc
            if prefix:sub(1, 1) == "i" then
              desc = desc:gsub(" with ws", "")
            end
            ret[#ret + 1] = { prefix .. obj[1], desc = obj.desc }
          end
        end

        require("which-key").add(ret, { notify = false })
      '';
    };

    "mini.surround" = {
      package = pkgs.vimPlugins.mini-surround;
      setupModule = "mini.surround";
      event = [
        {
          event = "User";
          pattern = "LazyFile";
        }
      ];
      keys = [
        {
          key = "gsa";
          mode = ["n" "x"];
          desc = "Add Surrounding";
        }
        {
          key = "gsd";
          mode = "n";
          desc = "Delete Surrounding";
        }
        {
          key = "gsf";
          mode = "n";
          desc = "Find Right Surrounding";
        }
        {
          key = "gsF";
          mode = "n";
          desc = "Find Left Surrounding";
        }
        {
          key = "gsh";
          mode = "n";
          desc = "Highlight Surrounding";
        }
        {
          key = "gsr";
          mode = "n";
          desc = "Replace Surrounding";
        }
        {
          key = "gsn";
          mode = "n";
          desc = "Update `MiniSurround.config.n_lines`";
        }
      ];
      setupOpts = {
        mappings = {
          add = "gsa";
          delete = "gsd";
          find = "gsf";
          find_left = "gsF";
          highlight = "gsh";
          replace = "gsr";
          update_n_lines = "gsn";
        };
      };
    };

    "yanky.nvim" = {
      package = pkgs.vimPlugins.yanky-nvim;
      setupModule = "yanky";
      event = [
        {
          event = "User";
          pattern = "LazyFile";
        }
      ];
      keys = [
        {
          key = "<leader>p";
          mode = ["n" "x"];
          desc = "Open Yank History";
          action = "function() require('snacks').picker.yanky() end";
          lua = true;
        }
        {
          key = "y";
          mode = ["n" "x"];
          desc = "Yank Text";
          action = "<Plug>(YankyYank)";
        }
        {
          key = "p";
          mode = ["n" "x"];
          desc = "Put Text After Cursor";
          action = "<Plug>(YankyPutAfter)";
        }
        {
          key = "P";
          mode = ["n" "x"];
          desc = "Put Text Before Cursor";
          action = "<Plug>(YankyPutBefore)";
        }
        {
          key = "gp";
          mode = ["n" "x"];
          desc = "Put Text After Selection";
          action = "<Plug>(YankyGPutAfter)";
        }
        {
          key = "gP";
          mode = ["n" "x"];
          desc = "Put Text Before Selection";
          action = "<Plug>(YankyGPutBefore)";
        }
        {
          key = "[y";
          mode = "n";
          desc = "Cycle Forward Through Yank History";
          action = "<Plug>(YankyCycleForward)";
        }
        {
          key = "]y";
          mode = "n";
          desc = "Cycle Backward Through Yank History";
          action = "<Plug>(YankyCycleBackward)";
        }
        {
          key = "]p";
          mode = "n";
          desc = "Put Indented After Cursor (Linewise)";
          action = "<Plug>(YankyPutIndentAfterLinewise)";
        }
        {
          key = "[p";
          mode = "n";
          desc = "Put Indented Before Cursor (Linewise)";
          action = "<Plug>(YankyPutIndentBeforeLinewise)";
        }
        {
          key = "]P";
          mode = "n";
          desc = "Put Indented After Cursor (Linewise)";
          action = "<Plug>(YankyPutIndentAfterLinewise)";
        }
        {
          key = "[P";
          mode = "n";
          desc = "Put Indented Before Cursor (Linewise)";
          action = "<Plug>(YankyPutIndentBeforeLinewise)";
        }
        {
          key = ">p";
          mode = "n";
          desc = "Put and Indent Right";
          action = "<Plug>(YankyPutIndentAfterShiftRight)";
        }
        {
          key = "<p";
          mode = "n";
          desc = "Put and Indent Left";
          action = "<Plug>(YankyPutIndentAfterShiftLeft)";
        }
        {
          key = ">P";
          mode = "n";
          desc = "Put Before and Indent Right";
          action = "<Plug>(YankyPutIndentBeforeShiftRight)";
        }
        {
          key = "<P";
          mode = "n";
          desc = "Put Before and Indent Left";
          action = "<Plug>(YankyPutIndentBeforeShiftLeft)";
        }
        {
          key = "=p";
          mode = "n";
          desc = "Put After Applying a Filter";
          action = "<Plug>(YankyPutAfterFilter)";
        }
        {
          key = "=P";
          mode = "n";
          desc = "Put Before Applying a Filter";
          action = "<Plug>(YankyPutBeforeFilter)";
        }
      ];
      setupOpts = {
        system_clipboard = {
          sync_with_ring = true;
        };
        highlight = {timer = 150;};
      };
    };

    "blink.cmp" = {
      package = pkgs.vimPlugins.blink-cmp;
      event = ["InsertEnter" "CmdlineEnter"];
      setupOpts = {
        snippets = {
          preset = "default";
        };
        appearance = {
          use_nvim_cmp_as_default = false;
          nerd_font_variant = "mono";
          kind_icons = {
            Array = " ";
            Boolean = "󰨙 ";
            Class = " ";
            Color = " ";
            Constant = "󰏿 ";
            Constructor = " ";
            Enum = " ";
            EnumMember = " ";
            Event = " ";
            Field = " ";
            File = " ";
            Folder = " ";
            Function = "󰊕 ";
            Interface = " ";
            Keyword = " ";
            Method = "󰊕 ";
            Module = " ";
            Namespace = "󰦮 ";
            Null = " ";
            Number = "󰎠 ";
            Object = " ";
            Operator = " ";
            Package = " ";
            Property = " ";
            Reference = " ";
            Snippet = "󱄽 ";
            String = " ";
            Struct = "󰆼 ";
            Text = " ";
            TypeParameter = " ";
            Unit = " ";
            Value = " ";
            Variable = "󰀫 ";
          };
        };
        completion = {
          accept = {
            auto_brackets = {
              enabled = true;
            };
          };
          menu = {
            draw = {
              treesitter = ["lsp"];
              columns = [
                {
                  __unkeyed-1 = "label";
                  __unkeyed-2 = "label_description";
                  gap = 1;
                }
                {
                  __unkeyed-1 = "kind_icon";
                  __unkeyed-2 = "kind";
                  gap = 1;
                }
                "source"
              ];
            };
          };
          documentation = {
            auto_show = true;
            auto_show_delay_ms = 200;
          };
          ghost_text = {
            enabled = true;
          };
        };
        sources = {
          default = ["lsp" "path" "snippets" "buffer"];
        };
        cmdline = {
          enabled = true;
          keymap = {
            preset = "cmdline";
          };
          completion = {
            list = {
              selection = {
                preselect = false;
              };
            };
            menu = {
              auto_show = lib.generators.mkLuaInline "function(ctx) return vim.fn.getcmdtype() == ':' end";
            };
            ghost_text = {
              enabled = true;
            };
          };
        };
        keymap = {
          preset = "enter";
          "<C-y>" = ["select_and_accept"];
        };
      };
    };

    "friendly-snippets" = {
      package = pkgs.vimPlugins.friendly-snippets;
    };
  };
}
