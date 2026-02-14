{
  pkgs,
  lib,
  ...
}: {
  programs.neovim = {
    plugins = with pkgs.vimPlugins; [
      plenary-nvim
      nui-nvim
      nvim-nio
    ];

    spec.plugins = {
      "snacks.nvim" = {
        package = pkgs.vimPlugins.snacks-nvim;
        setupModule = "snacks";
        event = ["UIEnter"];
        extraLuaBefore = ''
          function term_nav(dir)
            return function(self)
              return self:is_floating() and "<c-" .. dir .. ">" or vim.schedule(function()
                vim.cmd.wincmd(dir)
              end)
            end
          end
        '';
        setupOpts = {
          bigfile = {enabled = true;};
          explorer = {
            enabled = true;
            replace_netrw = true;
          };
          image = {enabled = true;};
          indent = {
            enabled = true;
            indent = {char = "▏";};
            scope = {
              underline = true;
              char = "▏";
            };
          };
          input = {enabled = true;};
          notifier = {enabled = true;};
          picker = {
            enabled = true;
            actions = {
              toggle_cwd = lib.generators.mkLuaInline ''
                function(p)
                  local root = vim.fs.normalize(vim.uv.cwd() or ".")
                  local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
                  local current = p:cwd()
                  p:set_cwd(current == root and cwd or root)
                  p:find()
                end
              '';
              trouble_open = lib.generators.mkLuaInline ''
                function(...)
                  return require("trouble.sources.snacks").actions.trouble_open.action(...)
                end
              '';
            };
            sources = {
              files = {hidden = true;};
              explorer = {
                hidden = true;
                ignored = true;
                exclude = [".git" ".DS_Store" "node_modules" ".next" ".cache" "target" "dist" "build"];
              };
            };
          };
          quickfile = {enabled = true;};
          terminal = {
            win = {
              keys = {
                nav_h = lib.generators.mkLuaInline ''{ "<C-h>", term_nav("h"), desc = "Go to Left Window", expr = true, mode = "t" }'';
                nav_j = lib.generators.mkLuaInline ''{ "<C-j>", term_nav("j"), desc = "Go to Lower Window", expr = true, mode = "t" }'';
                nav_k = lib.generators.mkLuaInline ''{ "<C-k>", term_nav("k"), desc = "Go to Upper Window", expr = true, mode = "t" }'';
                nav_l = lib.generators.mkLuaInline ''{ "<C-l>", term_nav("l"), desc = "Go to Right Window", expr = true, mode = "t" }'';
              };
            };
          };
          scope = {enabled = true;};
          statuscolumn = {enabled = true;};
          words = {enabled = true;};
        };
        extraLuaAfter = ''
          local function set_indent_highlights()
            local palette = require("catppuccin.palettes").get_palette()
            vim.api.nvim_set_hl(0, "SnacksIndent", { fg = palette.surface0 })
          end
          set_indent_highlights()
          vim.api.nvim_create_autocmd("ColorScheme", {
            callback = set_indent_highlights,
          })
        '';
        keymaps = [
          {
            key = "<leader>.";
            mode = "n";
            desc = "Toggle Scratch Buffer";
            action = "function() require('snacks').scratch() end";
            lua = true;
          }
          {
            key = "<leader>S";
            mode = "n";
            desc = "Select Scratch Buffer";
            action = "function() require('snacks').scratch.select() end";
            lua = true;
          }
          {
            key = "<leader>dps";
            mode = "n";
            desc = "Profiler Scratch Buffer";
            action = "function() require('snacks').profiler.scratch() end";
            lua = true;
          }
          {
            key = "<leader>n";
            mode = "n";
            desc = "Notification History";
            action = "function() require('snacks').picker.notifications() end";
            lua = true;
          }
          {
            key = "<leader>un";
            mode = "n";
            desc = "Dismiss All Notifications";
            action = "function() require('snacks').notifier.hide() end";
            lua = true;
          }
          {
            key = "<leader>bd";
            mode = "n";
            desc = "Delete Buffer";
            action = "function() require('snacks').bufdelete() end";
            lua = true;
            silent = true;
          }
          {
            key = "<leader>bo";
            mode = "n";
            desc = "Delete Other Buffers";
            action = "function() require('snacks').bufdelete.other() end";
            lua = true;
            silent = true;
          }
          {
            key = "<leader>p";
            mode = "n";
            desc = "Open Yank History";
            action = "function() require('snacks').picker.yanky() end";
            lua = true;
          }
          {
            key = "<leader>ud";
            mode = "n";
            desc = "Toggle Diagnostics";
            action = "function() require('snacks').toggle.diagnostics():toggle() end";
            lua = true;
          }
          {
            key = "<leader>uh";
            mode = "n";
            desc = "Toggle Inlay Hints";
            action = "function() if vim.lsp.inlay_hint then require('snacks').toggle.inlay_hints():toggle() end end";
            lua = true;
          }
          {
            key = "<leader>gg";
            mode = "n";
            desc = "Lazygit (cwd)";
            action = "function() require('snacks').lazygit() end";
            lua = true;
          }
          {
            key = "<leader>gB";
            mode = "n";
            desc = "Git Browse (open)";
            action = "function() require('snacks').gitbrowse() end";
            lua = true;
          }
          {
            key = "<leader>gY";
            mode = ["n" "x"];
            desc = "Git Browse (copy)";
            action = "function() require('snacks').gitbrowse({ open = function(url) vim.fn.setreg('+', url) end, notify = false }) end";
            lua = true;
          }
          {
            key = "<leader>wm";
            mode = "n";
            desc = "Toggle Zoom";
            action = "function() require('snacks').toggle.zoom():toggle() end";
            lua = true;
          }
          {
            key = "<leader>uz";
            mode = "n";
            desc = "Toggle Zen Mode";
            action = "function() require('snacks').toggle.zen():toggle() end";
            lua = true;
          }
          {
            key = "<localleader>r";
            mode = ["n" "x"];
            desc = "Run Lua";
            action = "function() require('snacks').debug.run() end";
            lua = true;
          }
          {
            key = "-";
            mode = "n";
            desc = "Explorer Snacks (cwd)";
            action = "function() require('snacks').explorer() end";
            lua = true;
          }
          {
            key = "<leader>,";
            mode = "n";
            desc = "Buffers";
            action = "function() require('snacks').picker.buffers() end";
            lua = true;
          }
          {
            key = "<leader>/";
            mode = "n";
            desc = "Grep (Root Dir)";
            action = "function() require('snacks').picker.grep() end";
            lua = true;
          }
          {
            key = "<leader>:";
            mode = "n";
            desc = "Command History";
            action = "function() require('snacks').picker.command_history() end";
            lua = true;
          }
          {
            key = "<leader><space>";
            mode = "n";
            desc = "Find Files (Root Dir)";
            action = "function() require('snacks').picker.files() end";
            lua = true;
          }
          {
            key = "<leader>fb";
            mode = "n";
            desc = "Buffers";
            action = "function() require('snacks').picker.buffers() end";
            lua = true;
          }
          {
            key = "<leader>fB";
            mode = "n";
            desc = "Buffers (all)";
            action = "function() require('snacks').picker.buffers({ hidden = true, nofile = true }) end";
            lua = true;
          }
          {
            key = "<leader>ff";
            mode = "n";
            desc = "Find Files (Root Dir)";
            action = "function() require('snacks').picker.files() end";
            lua = true;
          }
          {
            key = "<leader>fF";
            mode = "n";
            desc = "Find Files (cwd)";
            action = "function() require('snacks').picker.files({ root = false }) end";
            lua = true;
          }
          {
            key = "<leader>fg";
            mode = "n";
            desc = "Find Files (git-files)";
            action = "function() require('snacks').picker.git_files() end";
            lua = true;
          }
          {
            key = "<leader>fr";
            mode = "n";
            desc = "Recent";
            action = "function() require('snacks').picker.recent() end";
            lua = true;
          }
          {
            key = "<leader>fR";
            mode = "n";
            desc = "Recent (cwd)";
            action = "function() require('snacks').picker.recent({ filter = { cwd = true }}) end";
            lua = true;
          }
          {
            key = "<leader>fp";
            mode = "n";
            desc = "Projects";
            action = "function() require('snacks').picker.projects() end";
            lua = true;
          }
          {
            key = "<leader>gd";
            mode = "n";
            desc = "Git Diff (hunks)";
            action = "function() require('snacks').picker.git_diff() end";
            lua = true;
          }
          {
            key = "<leader>gD";
            mode = "n";
            desc = "Git Diff (origin)";
            action = "function() require('snacks').picker.git_diff({ base = 'origin', group = true }) end";
            lua = true;
          }
          {
            key = "<leader>gs";
            mode = "n";
            desc = "Git Status";
            action = "function() require('snacks').picker.git_status() end";
            lua = true;
          }
          {
            key = "<leader>gS";
            mode = "n";
            desc = "Git Stash";
            action = "function() require('snacks').picker.git_stash() end";
            lua = true;
          }
          {
            key = "<leader>gi";
            mode = "n";
            desc = "GitHub Issues (open)";
            action = "function() require('snacks').picker.gh_issue() end";
            lua = true;
          }
          {
            key = "<leader>gI";
            mode = "n";
            desc = "GitHub Issues (all)";
            action = "function() require('snacks').picker.gh_issue({ state = 'all' }) end";
            lua = true;
          }
          {
            key = "<leader>gp";
            mode = "n";
            desc = "GitHub Pull Requests (open)";
            action = "function() require('snacks').picker.gh_pr() end";
            lua = true;
          }
          {
            key = "<leader>gP";
            mode = "n";
            desc = "GitHub Pull Requests (all)";
            action = "function() require('snacks').picker.gh_pr({ state = 'all' }) end";
            lua = true;
          }
          {
            key = "<leader>sb";
            mode = "n";
            desc = "Buffer Lines";
            action = "function() require('snacks').picker.lines() end";
            lua = true;
          }
          {
            key = "<leader>sB";
            mode = "n";
            desc = "Grep Open Buffers";
            action = "function() require('snacks').picker.grep_buffers() end";
            lua = true;
          }
          {
            key = "<leader>sg";
            mode = "n";
            desc = "Grep (Root Dir)";
            action = "function() require('snacks').picker.grep() end";
            lua = true;
          }
          {
            key = "<leader>sG";
            mode = "n";
            desc = "Grep (cwd)";
            action = "function() require('snacks').picker.grep({ root = false }) end";
            lua = true;
          }
          {
            key = "<leader>sp";
            mode = "n";
            desc = "Search for Plugin Spec";
            action = "function() require('snacks').picker.lazy() end";
            lua = true;
          }
          {
            key = "<leader>sw";
            mode = ["n" "x"];
            desc = "Visual selection or word (Root Dir)";
            action = "function() require('snacks').picker.grep_word() end";
            lua = true;
          }
          {
            key = "<leader>sW";
            mode = ["n" "x"];
            desc = "Visual selection or word (cwd)";
            action = "function() require('snacks').picker.grep_word({ root = false }) end";
            lua = true;
          }
          {
            key = "<leader>s\"";
            mode = "n";
            desc = "Registers";
            action = "function() require('snacks').picker.registers() end";
            lua = true;
          }
          {
            key = "<leader>s/";
            mode = "n";
            desc = "Search History";
            action = "function() require('snacks').picker.search_history() end";
            lua = true;
          }
          {
            key = "<leader>sa";
            mode = "n";
            desc = "Autocmds";
            action = "function() require('snacks').picker.autocmds() end";
            lua = true;
          }
          {
            key = "<leader>sc";
            mode = "n";
            desc = "Command History";
            action = "function() require('snacks').picker.command_history() end";
            lua = true;
          }
          {
            key = "<leader>sC";
            mode = "n";
            desc = "Commands";
            action = "function() require('snacks').picker.commands() end";
            lua = true;
          }
          {
            key = "<leader>sd";
            mode = "n";
            desc = "Diagnostics";
            action = "function() require('snacks').picker.diagnostics() end";
            lua = true;
          }
          {
            key = "<leader>sD";
            mode = "n";
            desc = "Buffer Diagnostics";
            action = "function() require('snacks').picker.diagnostics_buffer() end";
            lua = true;
          }
          {
            key = "<leader>sh";
            mode = "n";
            desc = "Help Pages";
            action = "function() require('snacks').picker.help() end";
            lua = true;
          }
          {
            key = "<leader>sH";
            mode = "n";
            desc = "Highlights";
            action = "function() require('snacks').picker.highlights() end";
            lua = true;
          }
          {
            key = "<leader>si";
            mode = "n";
            desc = "Icons";
            action = "function() require('snacks').picker.icons() end";
            lua = true;
          }
          {
            key = "<leader>sj";
            mode = "n";
            desc = "Jumps";
            action = "function() require('snacks').picker.jumps() end";
            lua = true;
          }
          {
            key = "<leader>sk";
            mode = "n";
            desc = "Keymaps";
            action = "function() require('snacks').picker.keymaps() end";
            lua = true;
          }
          {
            key = "<leader>sl";
            mode = "n";
            desc = "Location List";
            action = "function() require('snacks').picker.loclist() end";
            lua = true;
          }
          {
            key = "<leader>sM";
            mode = "n";
            desc = "Man Pages";
            action = "function() require('snacks').picker.man() end";
            lua = true;
          }
          {
            key = "<leader>sm";
            mode = "n";
            desc = "Marks";
            action = "function() require('snacks').picker.marks() end";
            lua = true;
          }
          {
            key = "<leader>sR";
            mode = "n";
            desc = "Resume";
            action = "function() require('snacks').picker.resume() end";
            lua = true;
          }
          {
            key = "<leader>sq";
            mode = "n";
            desc = "Quickfix List";
            action = "function() require('snacks').picker.qflist() end";
            lua = true;
          }
          {
            key = "<leader>su";
            mode = "n";
            desc = "Undotree";
            action = "function() require('snacks').picker.undo() end";
            lua = true;
          }
        ];
      };
    };
  };
}
