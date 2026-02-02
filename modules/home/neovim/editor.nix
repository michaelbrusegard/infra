{ pkgs, ... }: {
  programs.nvf.settings.vim = {
    lazy.plugins = {
      "grug-far.nvim" = {
        package = pkgs.vimPlugins.grug-far-nvim;
        cmd = [ "GrugFar" "GrugFarWithin" ];
        setupOpts = { headerMaxWidth = 80; };
        keys = [{
          key = "<leader>sr";
          mode = [ "n" "x" ];
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
          desc = "Search and Replace";
        }];
      };
    };
    utility.motion.flash-nvim = {
      enable = true;
      setupOpts = { };
      mappings = {
        jump = "s";
        treesitter = "S";
        remote = "r";
        treesitter_search = "R";
        toggle = "<c-s>";
      };
    };
    maps.normal = {
      "<c-space>" = {
        action = ''
          function()
            require("flash").treesitter({
              actions = {
                ["<c-space>"] = "next",
                ["<BS>"] = "prev"
              }
            }) 
          end
        '';
        lua = true;
        desc = "Treesitter Incremental Selection";
        mode = [ "n" "o" "x" ];
      };
    };
    lsp.trouble = {
      enable = true;
      setupOpts = {
        modes = {
          lsp = {
            win = { position = "right"; };
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
    maps.normal = {
      "[q" = {
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
        desc = "Previous Trouble/Quickfix Item";
      };
      "]q" = {
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
        desc = "Next Trouble/Quickfix Item";
      };
    };
    notes.todo-comments = {
      enable = true;
      setupOpts = { };
      mappings = {
        trouble = "<leader>xt";
        telescope = "<leader>st";
      };
    };
    maps.normal = {
      "]t" = { action = "function() require('todo-comments').jump_next() end"; lua = true; desc = "Next Todo Comment"; };
      "[t" = { action = "function() require('todo-comments').jump_prev() end"; lua = true; desc = "Previous Todo Comment"; };
      "<leader>xT" = { action = "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>"; desc = "Todo/Fix/Fixme (Trouble)"; };
      "<leader>sT" = { action = "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>"; desc = "Todo/Fix/Fixme"; };
    };
    git.gitsigns = {
      enable = true;
      setupOpts = {
        signs = {
          add = { text = "▎"; };
          change = { text = "▎"; };
          delete = { text = ""; };
          topdelete = { text = ""; };
          changedelete = { text = "▎"; };
          untracked = { text = "▎"; };
        };
        signs_staged = {
          add = { text = "▎"; };
          change = { text = "▎"; };
          delete = { text = ""; };
          topdelete = { text = ""; };
          changedelete = { text = "▎"; };
        };
        on_attach = ''
          function(buffer)
            local gs = package.loaded.gitsigns

            local function map(mode, l, r, desc)
              vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc, silent = true })
            end

            -- Navigation
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

            -- Actions
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

            -- Text Object
            map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "GitSigns Select Hunk")
          end
        '';
      };
    };
    binds.whichKey = {
      enable = true;
      setupOpts = {
        preset = "helix";
        spec = [
          { __unkeyed-1 = "<leader><tab>"; group = "tabs"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>c"; group = "code"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>d"; group = "debug"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>dp"; group = "profiler"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>f"; group = "file/find"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>g"; group = "git"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>gh"; group = "hunks"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>q"; group = "quit/session"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>s"; group = "search"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>u"; group = "ui"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "<leader>x"; group = "diagnostics/quickfix"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "["; group = "prev"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "]"; group = "next"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "g"; group = "goto"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "gs"; group = "surround"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "z"; group = "fold"; mode = [ "n" "x" ]; }
          { __unkeyed-1 = "gx"; desc = "Open with system app"; mode = [ "n" "x" ]; }
          {
            __unkeyed-1 = "<leader>b";
            group = "buffer";
            expand = "function() return require('which-key.extras').expand.buf() end";
            mode = [ "n" "x" ];
          }
          {
            __unkeyed-1 = "<leader>w";
            group = "windows";
            proxy = "<c-w>";
            expand = "function() return require('which-key.extras').expand.win() end";
            mode = [ "n" "x" ];
          }
        ];
      };
    };
    maps.normal = {
      "<leader>?" = {
        action = "function() require('which-key').show({ global = false }) end";
        lua = true;
        desc = "Buffer Keymaps (which-key)";
      };
      "<c-w><space>" = {
        action = "function() require('which-key').show({ keys = '<c-w>', loop = true }) end";
        lua = true;
        desc = "Window Hydra Mode (which-key)";
      };
    };
  };
}
