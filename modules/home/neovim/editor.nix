{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim = {
    lazy.plugins = {
      "grug-far.nvim" = {
        package = pkgs.vimPlugins.grug-far-nvim;
        cmd = ["GrugFar" "GrugFarWithin"];
        setupOpts = {headerMaxWidth = 80;};
        keys = [
          {
            key = "<leader>sr";
            mode = ["n" "x"];
            desc = "Search and Replace";
            action = ''
              function()
                local grug = require("grug-far")
                local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
                grug.open({
                  transient = true,
                  prefills = {
                    filesFilter = ext and ext ~= "" and "*." .. ext or nil,
                  },
                })
              end
            '';
            lua = true;
          }
        ];
      };
      "dial.nvim" = {
        package = pkgs.vimPlugins.dial-nvim;
        setupModule = "dial";
        setupOpts = {};
        keys = [
          {
            key = "<C-a>";
            mode = ["n" "v"];
            desc = "Increment";
            action = "function() return _G.dial(true) end";
            lua = true;
            expr = true;
            silent = true;
          }
          {
            key = "<C-x>";
            mode = ["n" "v"];
            desc = "Decrement";
            action = "function() return _G.dial(false) end";
            lua = true;
            expr = true;
            silent = true;
          }
          {
            key = "g<C-a>";
            mode = ["n" "x"];
            desc = "Increment";
            action = "function() return _G.dial(true, true) end";
            lua = true;
            expr = true;
            silent = true;
          }
          {
            key = "g<C-x>";
            mode = ["n" "x"];
            desc = "Decrement";
            action = "function() return _G.dial(false, true) end";
            lua = true;
            expr = true;
            silent = true;
          }
        ];
        after = ''
          local augend = require("dial.augend")

          local dial_config = {
            dials_by_ft = {
              css = "css", vue = "vue", javascript = "typescript",
              typescript = "typescript", typescriptreact = "typescript",
              javascriptreact = "typescript", json = "json", lua = "lua",
              markdown = "markdown", sass = "css", scss = "css", python = "python",
            },
            groups = {
              default = {
                augend.integer.alias.decimal,
                augend.integer.alias.decimal_int,
                augend.integer.alias.hex,
                augend.date.alias["%Y/%m/%d"],
                augend.constant.alias.bool,
                augend.constant.new({ elements = { "&&", "||" }, word = false, cyclic = true }),
                augend.constant.new({
                  elements = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth" },
                  word = false, cyclic = true
                }),
                augend.constant.new({
                  elements = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" },
                  word = true, cyclic = true
                }),
                augend.constant.new({
                  elements = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" },
                  word = true, cyclic = true
                }),
                augend.constant.new({ elements = { "True", "False" }, word = true, cyclic = true }),
              },
              vue = {
                augend.constant.new({ elements = { "let", "const" } }),
                augend.hexcolor.new({ case = "lower" }),
                augend.hexcolor.new({ case = "upper" }),
              },
              typescript = {
                augend.constant.new({ elements = { "let", "const" } }),
              },
              css = {
                augend.hexcolor.new({ case = "lower" }),
                augend.hexcolor.new({ case = "upper" }),
              },
              markdown = {
                augend.constant.new({ elements = { "[ ]", "[x]" }, word = false, cyclic = true }),
                augend.misc.alias.markdown_header,
              },
              json = { augend.semver.alias.semver },
              lua = {
                augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
              },
              python = {
                augend.constant.new({ elements = { "and", "or" } }),
              },
            },
          }

          for name, group in pairs(dial_config.groups) do
            if name ~= "default" then
              vim.list_extend(group, dial_config.groups.default)
            end
          end

          require("dial.config").augends:register_group(dial_config.groups)
          vim.g.dials_by_ft = dial_config.dials_by_ft

          function _G.dial(increment, g)
            local mode = vim.fn.mode(true)
            local is_visual = mode == "v" or mode == "V" or mode == "\22"
            local func = (increment and "inc" or "dec") .. (g and "_g" or "_") .. (is_visual and "visual" or "normal")
            local group = vim.g.dials_by_ft[vim.bo.filetype] or "default"
            return require("dial.map")[func](group)
          end
        '';
      };
      "codediff.nvim" = {
        package = pkgs.vimPlugins.codediff-nvim;
        setupModule = "codediff";
        setupOpts = {};
        cmd = ["CodeDiff"];
      };
    };

    lsp.trouble = {
      enable = true;
      setupOpts = {
        modes = {
          lsp = {
            win = {position = "right";};
          };
        };
      };
      mappings = {
        workspaceDiagnostics = "<leader>xx";
        documentDiagnostics = "<leader>xX";
        symbols = "<leader>cs";
        lspReferences = "<leader>cS";
        locList = "<leader>xL";
        quickfix = "<leader>xQ";
      };
    };

    notes.todo-comments = {
      enable = true;
      mappings = {
        trouble = "<leader>xt";
        telescope = "<leader>st";
      };
    };

    ui.breadcrumbs = {
      enable = true;
      lualine.winbar.enable = false;
      navbuddy.enable = true;
    };

    mini.move = {
      enable = true;
      setupOpts = {
        mappings = {
          left = "<s-h>";
          right = "<s-l>";
          down = "<s-j>";
          up = "<s-k>";
          line_left = "";
          line_right = "";
          line_down = "";
          line_up = "";
        };
        options = {
          reindent_linewise = true;
        };
      };
    };

    # Keymaps
    keymaps = [
      {
        key = "[q";
        mode = "n";
        desc = "Previous Trouble/Quickfix Item";
        action = ''
          function()
            if require("trouble").is_open() then
              require("trouble").prev({ skip_groups = true, jump = true })
            else
              local ok, err = pcall(vim.cmd.cprev)
              if not ok then
                vim.notify(err, vim.log.levels.ERROR)
              end
            end
          end
        '';
        lua = true;
      }
      {
        key = "]q";
        mode = "n";
        desc = "Next Trouble/Quickfix Item";
        action = ''
          function()
            if require("trouble").is_open() then
              require("trouble").next({ skip_groups = true, jump = true })
            else
              local ok, err = pcall(vim.cmd.cnext)
              if not ok then vim.notify(err, vim.log.levels.ERROR)
              end
            end
          end
        '';
        lua = true;
      }
      {
        key = "]t";
        mode = "n";
        desc = "Next Todo Comment";
        action = "function() require('todo-comments').jump_next() end";
        lua = true;
      }
      {
        key = "[t";
        mode = "n";
        desc = "Previous Todo Comment";
        action = "function() require('todo-comments').jump_prev() end";
        lua = true;
      }
      {
        key = "<leader>xt";
        mode = "n";
        desc = "Todo (Trouble)";
        action = "function() require('snacks').picker.todo_comments() end";
        lua = true;
      }
      {
        key = "<leader>xT";
        mode = "n";
        desc = "Todo/Fix/Fixme (Trouble)";
        action = "function() require('snacks').picker.todo_comments({ keywords = { 'TODO', 'FIX', 'FIXME' } }) end";
        lua = true;
      }
      {
        key = "<leader>st";
        mode = "n";
        desc = "Todo";
        action = "function() require('snacks').picker.todo_comments() end";
        lua = true;
      }
      {
        key = "<leader>sT";
        mode = "n";
        desc = "Todo/Fix/Fixme";
        action = "function() require('snacks').picker.todo_comments({ keywords = { 'TODO', 'FIX', 'FIXME' } }) end";
        lua = true;
      }
      {
        key = "<leader>?";
        mode = "n";
        desc = "Buffer Keymaps (which-key)";
        action = "function() require('which-key').show({ global = false }) end";
        lua = true;
      }
      {
        key = "<c-w><space>";
        mode = "n";
        desc = "Window Hydra Mode (which-key)";
        action = "function() require('which-key').show({ keys = '<c-w>', loop = true }) end";
        lua = true;
      }
    ];

    # Gitsigns
    git.gitsigns = {
      enable = true;
      setupOpts = {
        signs = {
          add = {text = "▎";};
          change = {text = "▎";};
          delete = {text = "";};
          topdelete = {text = "";};
          changedelete = {text = "▎";};
          untracked = {text = "▎";};
        };
        signs_staged = {
          add = {text = "▎";};
          change = {text = "▎";};
          delete = {text = "";};
          topdelete = {text = "";};
          changedelete = {text = "▎";};
        };
        on_attach = lib.generators.mkLuaInline ''
          function(buffer)
            local gs = package.loaded.gitsigns

            local function map(mode, l, r, desc)
              vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc, silent = true })
            end

            map("n", "]h", function()
              if vim.wo.diff then
                vim.cmd.normal({ "]c", bang = true })
              else
                gs.nav_hunk("next")
              end
            end, "Next Hunk")

            map("n", "[h", function()
              if vim.wo.diff then
                vim.cmd.normal({ "[c", bang = true })
              else
                gs.nav_hunk("prev")
              end
            end, "Prev Hunk")

            map("n", "]H", function() gs.nav_hunk("last") end, "Last Hunk")
            map("n", "[H", function() gs.nav_hunk("first") end, "First Hunk")

            map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
            map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
            map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
            map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo Stage Hunk")
            map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
            map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
            map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame Line")
            map("n", "<leader>ghB", function() gs.blame() end, "Blame Buffer")
            map("n", "<leader>ghd", gs.diffthis, "Diff This")
            map("n", "<leader>ghD", function() gs.diffthis("~") end, "Diff This ~")
            map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "GitSigns Select Hunk")
          end
        '';
      };
    };

    luaConfigRC.navic-attach = ''
      require("nvim-navic").setup({
        separator = " ",
        highlight = true,
        depth_limit = 5,
        lazy_update_context = true,
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.supports_method("textDocument/documentSymbol") then
            require("nvim-navic").attach(client, args.buf)
          end
        end,
      })
    '';

    binds.whichKey = {
      enable = true;
      setupOpts = {
        preset = "helix";
        delay = 50;
        spec = lib.generators.mkLuaInline ''
          {
            mode = { "n", "x" },
            { "<leader><tab>", group = "tabs" },
            { "<leader>c", group = "code" },
            { "<leader>d", group = "debug" },
            { "<leader>dp", group = "profiler" },
            { "<leader>f", group = "file/find" },
            { "<leader>g", group = "git" },
            { "<leader>gh", group = "hunks" },
            { "<leader>q", group = "quit/session" },
            { "<leader>s", group = "search" },
            { "<leader>u", group = "ui" },
            { "<leader>x", group = "diagnostics/quickfix" },
            { "[", group = "prev" },
            { "]", group = "next" },
            { "g", group = "goto" },
            { "s", group = "surround" },
            { "z", group = "fold" },
            { "gx", desc = "Open with system app" },
            {
              "<leader>b",
              group = "buffer",
              expand = function()
                return require("which-key.extras").expand.buf()
              end,
            },
            {
              "<leader>w",
              group = "windows",
              proxy = "<c-w>",
              expand = function()
                return require("which-key.extras").expand.win()
              end,
            },
            { "<leader>a", group = "ai", mode = "n" },
            { "<leader>t", group = "test", mode = "n" },
            { "<leader>R", group = "rest", mode = "n" },
          }
        '';
      };
    };
  };
}
