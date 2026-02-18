{
  pkgs,
  lib,
  ...
}: let
  first-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "first.nvim";
    version = "2024-04-17";
    src = pkgs.fetchFromGitHub {
      owner = "Laellekoenig";
      repo = "first.nvim";
      rev = "996023191adba3c0abcc2c2939c47e9733529437";
      hash = "sha256-fyGopwXb7C7PXLLjtbqP/cLexUpW2rimyvJ4NFHpRPo=";
    };
  };
in {
  programs.neovim.spec.plugins = {
    "grug-far.nvim" = {
      package = pkgs.vimPlugins.grug-far-nvim;
      command = ["GrugFar" "GrugFarWithin"];
      setupModule = "grug-far";
      setupOpts = {headerMaxWidth = 80;};
      keymaps = [
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
      event = ["BufReadPost" "BufNewFile"];
      keymaps = [
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
      extraLuaAfter = ''
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

    "diffview.nvim" = {
      package = pkgs.vimPlugins.diffview-nvim;
      command = ["DiffviewOpen" "DiffviewFileHistory"];
      setupModule = "diffview";
      setupOpts = {
        view.merge_tool.layout = "diff3_mixed";
      };
    };

    "todo-comments.nvim" = {
      package = pkgs.vimPlugins.todo-comments-nvim;
      event = ["BufReadPost" "BufNewFile"];
      setupModule = "todo-comments";
      keymaps = [
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
          action = "<cmd>Trouble todo toggle<cr>";
        }
        {
          key = "<leader>xT";
          mode = "n";
          desc = "Todo/Fix/Fixme (Trouble)";
          action = "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>";
        }
        {
          key = "<leader>st";
          mode = "n";
          desc = "Todo";
          action = "<cmd>TodoTelescope<cr>";
        }
        {
          key = "<leader>sT";
          mode = "n";
          desc = "Todo/Fix/Fixme";
          action = "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>";
        }
      ];
    };

    "trouble.nvim" = {
      package = pkgs.vimPlugins.trouble-nvim;
      event = ["BufReadPost" "BufNewFile"];
      setupModule = "trouble";
      setupOpts = {
        modes = {
          lsp = {
            win = {position = "right";};
          };
        };
      };
      keymaps = [
        {
          key = "<leader>xx";
          mode = "n";
          desc = "Workspace Diagnostics (Trouble)";
          action = "<cmd>Trouble diagnostics toggle<cr>";
        }
        {
          key = "<leader>xX";
          mode = "n";
          desc = "Document Diagnostics (Trouble)";
          action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
        }
        {
          key = "<leader>cs";
          mode = "n";
          desc = "Symbols (Trouble)";
          action = "<cmd>Trouble symbols toggle focus=false<cr>";
        }
        {
          key = "<leader>cS";
          mode = "n";
          desc = "LSP References (Trouble)";
          action = "<cmd>Trouble lsp toggle focus=false win.position=right<cr>";
        }
        {
          key = "<leader>xl";
          mode = "n";
          desc = "Location List (Trouble)";
          action = "<cmd>Trouble loclist toggle<cr>";
        }
        {
          key = "<leader>xq";
          mode = "n";
          desc = "Quickfix List (Trouble)";
          action = "<cmd>Trouble quickfix toggle<cr>";
        }
        {
          key = "[q";
          mode = "n";
          desc = "Previous Trouble Item";
          action = "function() require('trouble').prev({ skip_groups = true, jump = true }) end";
          lua = true;
        }
        {
          key = "]q";
          mode = "n";
          desc = "Next Trouble Item";
          action = "function() require('trouble').next({ skip_groups = true, jump = true }) end";
          lua = true;
        }
      ];
    };

    "which-key.nvim" = {
      package = pkgs.vimPlugins.which-key-nvim;
      event = ["UIEnter"];
      setupModule = "which-key";
      setupOpts = {
        preset = "helix";
        delay = 100;
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

    "nvim-navic" = {
      package = pkgs.vimPlugins.nvim-navic;
      event = ["LspAttach"];
      after = "nvim-lspconfig";
      setupModule = "nvim-navic";
      setupOpts = {
        separator = " ";
        highlight = true;
        depth_limit = 3;
        lazy_update_context = true;
        icons = {
          Array = " ";
          Boolean = "󰨙 ";
          Class = " ";
          Color = " ";
          Control = " ";
          Collapsed = " ";
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
          Key = " ";
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
      extraLuaAfter = ''
        vim.g.navic_silence = true
        vim.api.nvim_create_autocmd("LspAttach", {
          callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client and client.supports_method("textDocument/documentSymbol") then
              require("nvim-navic").attach(client, args.buf)
            end
          end,
        })
      '';
    };

    "gitsigns.nvim" = {
      package = pkgs.vimPlugins.gitsigns-nvim;
      event = ["BufReadPost" "BufNewFile"];
      setupModule = "gitsigns";
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

    "mini-move" = {
      package = pkgs.vimPlugins.mini-move;
      event = ["BufReadPost"];
      setupModule = "mini.move";
      setupOpts = {
        mappings = {
          left = "<S-h>";
          right = "<S-l>";
          down = "<S-j>";
          up = "<S-k>";
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

    "refactoring.nvim" = {
      package = pkgs.vimPlugins.refactoring-nvim;
      after = "nvim-treesitter";
      setupModule = "refactoring";
      setupOpts = {
        prompt_func_return_type = {
          go = false;
          java = false;
          cpp = false;
          c = false;
          h = false;
          hpp = false;
          cxx = false;
        };
        prompt_func_param_type = {
          go = false;
          java = false;
          cpp = false;
          c = false;
          h = false;
          hpp = false;
          cxx = false;
        };
        printf_statements = {};
        print_var_statements = {};
        show_success_message = true;
      };
      keymaps = [
        {
          key = "<leader>r";
          mode = ["n" "x"];
          desc = "+refactor";
          action = "function() end";
          lua = true;
        }
        {
          key = "<leader>rs";
          mode = ["n" "x"];
          desc = "Refactor";
          action = "function() require('refactoring').select_refactor() end";
          lua = true;
        }
        {
          key = "<leader>ri";
          mode = ["n" "x"];
          desc = "Inline Variable";
          action = "function() require('refactoring').refactor('Inline Variable') end";
          lua = true;
        }
        {
          key = "<leader>rb";
          mode = ["n" "x"];
          desc = "Extract Block";
          action = "function() require('refactoring').refactor('Extract Block') end";
          lua = true;
        }
        {
          key = "<leader>rF";
          mode = ["n" "x"];
          desc = "Extract Block To File";
          action = "function() require('refactoring').refactor('Extract Block To File') end";
          lua = true;
        }
        {
          key = "<leader>rP";
          mode = "n";
          desc = "Debug Print";
          action = "function() require('refactoring').debug.printf({ below = false }) end";
          lua = true;
        }
        {
          key = "<leader>rp";
          mode = ["n" "x"];
          desc = "Debug Print Variable";
          action = "function() require('refactoring').debug.print_var({ normal = true }) end";
          lua = true;
        }
        {
          key = "<leader>rc";
          mode = "n";
          desc = "Debug Cleanup";
          action = "function() require('refactoring').debug.cleanup({}) end";
          lua = true;
        }
        {
          key = "<leader>rf";
          mode = ["n" "x"];
          desc = "Extract Function";
          action = "function() require('refactoring').refactor('Extract Function') end";
          lua = true;
        }
        {
          key = "<leader>rF";
          mode = ["n" "x"];
          desc = "Extract Function To File";
          action = "function() require('refactoring').refactor('Extract Function To File') end";
          lua = true;
        }
        {
          key = "<leader>rx";
          mode = ["n" "x"];
          desc = "Extract Variable";
          action = "function() require('refactoring').refactor('Extract Variable') end";
          lua = true;
        }
      ];
    };

    "first-nvim" = {
      package = first-nvim;
      event = ["DeferredUIEnter"];
      setupModule = "first";
      setupOpts = {
        use_default_keymap = true;
        use_delete_and_change = false;
        inclusive_forward_delete = true;
        inclusive_backward_delete = true;
      };
    };
  };
}
