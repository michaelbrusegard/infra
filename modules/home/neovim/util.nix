{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec.plugins = {
    "snacks.nvim" = {
      package = pkgs.vimPlugins.snacks-nvim;
      setupModule = "snacks";
      event = ["VimEnter"];
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

    "mini.hipatterns" = {
      package = pkgs.vimPlugins.mini-hipatterns;
      event = ["BufReadPost" "BufNewFile"];
      extraLuaAfter = ''
        local hi = require("mini.hipatterns")
        local colors = {
          slate = { [50] = "f8fafc", [100] = "f1f5f9", [200] = "e2e8f0", [300] = "cbd5e1", [400] = "94a3b8", [500] = "64748b", [600] = "475569", [700] = "334155", [800] = "1e293b", [900] = "0f172a", [950] = "020617" },
          gray = { [50] = "f9fafb", [100] = "f3f4f6", [200] = "e5e7eb", [300] = "d1d5db", [400] = "9ca3af", [500] = "6b7280", [600] = "4b5563", [700] = "374151", [800] = "1f2937", [900] = "111827", [950] = "030712" },
          zinc = { [50] = "fafafa", [100] = "f4f4f5", [200] = "e4e4e7", [300] = "d4d4d8", [400] = "a1a1aa", [500] = "71717a", [600] = "52525b", [700] = "3f3f46", [800] = "27272a", [900] = "18181b", [950] = "09090B" },
          neutral = { [50] = "fafafa", [100] = "f5f5f5", [200] = "e5e5e5", [300] = "d4d4d4", [400] = "a3a3a3", [500] = "737373", [600] = "525252", [700] = "404040", [800] = "262626", [900] = "171717", [950] = "0a0a0a" },
          stone = { [50] = "fafaf9", [100] = "f5f5f4", [200] = "e7e5e4", [300] = "d6d3d1", [400] = "a8a29e", [500] = "78716c", [600] = "57534e", [700] = "44403c", [800] = "292524", [900] = "1c1917", [950] = "0a0a0a" },
          red = { [50] = "fef2f2", [100] = "fee2e2", [200] = "fecaca", [300] = "fca5a5", [400] = "f87171", [500] = "ef4444", [600] = "dc2626", [700] = "b91c1c", [800] = "991b1b", [900] = "7f1d1d", [950] = "450a0a" },
          orange = { [50] = "fff7ed", [100] = "ffedd5", [200] = "fed7aa", [300] = "fdba74", [400] = "fb923c", [500] = "f97316", [600] = "ea580c", [700] = "c2410c", [800] = "9a3412", [900] = "7c2d12", [950] = "431407" },
          amber = { [50] = "fffbeb", [100] = "fef3c7", [200] = "fde68a", [300] = "fcd34d", [400] = "fbbf24", [500] = "f59e0b", [600] = "d97706", [700] = "b45309", [800] = "92400e", [900] = "78350f", [950] = "451a03" },
          yellow = { [50] = "fefce8", [100] = "fef9c3", [200] = "fef08a", [300] = "fde047", [400] = "facc15", [500] = "eab308", [600] = "ca8a04", [700] = "a16207", [800] = "854d0e", [900] = "713f12", [950] = "422006" },
          lime = { [50] = "f7fee7", [100] = "ecfccb", [200] = "d9f99d", [300] = "bef264", [400] = "a3e635", [500] = "84cc16", [600] = "65a30d", [700] = "4d7c0f", [800] = "3f6212", [900] = "365314", [950] = "1a2e05" },
          green = { [50] = "f0fdf4", [100] = "dcfce7", [200] = "bbf7d0", [300] = "86efac", [400] = "4ade80", [500] = "22c55e", [600] = "16a34a", [700] = "15803d", [800] = "166534", [900] = "14532d", [950] = "052e16" },
          emerald = { [50] = "ecfdf5", [100] = "d1fae5", [200] = "a7f3d0", [300] = "6ee7b7", [400] = "34d399", [500] = "10b981", [600] = "059669", [700] = "047857", [800] = "065f46", [900] = "064e3b", [950] = "022c22" },
          teal = { [50] = "f0fdfa", [100] = "ccfbf1", [200] = "99f6e4", [300] = "5eead4", [400] = "2dd4bf", [500] = "14b8a6", [600] = "0d9488", [700] = "0f766e", [800] = "115e59", [900] = "134e4a", [950] = "042f2e" },
          cyan = { [50] = "ecfeff", [100] = "cffafe", [200] = "a5f3fc", [300] = "67e8f9", [400] = "22d3ee", [500] = "06b6d4", [600] = "0891b2", [700] = "0e7490", [800] = "155e75", [900] = "164e63", [950] = "083344" },
          sky = { [50] = "f0f9ff", [100] = "e0f2fe", [200] = "bae6fd", [300] = "7dd3fc", [400] = "38bdf8", [500] = "0ea5e9", [600] = "0284c7", [700] = "0369a1", [800] = "075985", [900] = "0c4a6e", [950] = "082f49" },
          blue = { [50] = "eff6ff", [100] = "dbeafe", [200] = "bfdbfe", [300] = "93c5fd", [400] = "60a5fa", [500] = "3b82f6", [600] = "2563eb", [700] = "1d4ed8", [800] = "1e40af", [900] = "1e3a8a", [950] = "172554" },
          indigo = { [50] = "eef2ff", [100] = "e0e7ff", [200] = "c7d2fe", [300] = "a5b4fc", [400] = "818cf8", [500] = "6366f1", [600] = "4f46e5", [700] = "4338ca", [800] = "3730a3", [900] = "312e81", [950] = "1e1b4b" },
          violet = { [50] = "f5f3ff", [100] = "ede9fe", [200] = "ddd6fe", [300] = "c4b5fd", [400] = "a78bfa", [500] = "8b5cf6", [600] = "7c3aed", [700] = "6d28d9", [800] = "5b21b6", [900] = "4c1d95", [950] = "2e1065" },
          purple = { [50] = "faf5ff", [100] = "f3e8ff", [200] = "e9d5ff", [300] = "d8b4fe", [400] = "c084fc", [500] = "a855f7", [600] = "9333ea", [700] = "7e22ce", [800] = "6b21a8", [900] = "581c87", [950] = "3b0764" },
          fuchsia = { [50] = "fdf4ff", [100] = "fae8ff", [200] = "f5d0fe", [300] = "f0abfc", [400] = "e879f9", [500] = "d946ef", [600] = "c026d3", [700] = "a21caf", [800] = "86198f", [900] = "701a75", [950] = "4a044e" },
          pink = { [50] = "fdf2f8", [100] = "fce7f3", [200] = "fbcfe8", [300] = "f9a8d4", [400] = "f472b6", [500] = "ec4899", [600] = "db2777", [700] = "be185d", [800] = "9d174d", [900] = "831843", [950] = "500724" },
          rose = { [50] = "fff1f2", [100] = "ffe4e6", [200] = "fecdd3", [300] = "fda4af", [400] = "fb7185", [500] = "f43f5e", [600] = "e11d48", [700] = "be123c", [800] = "9f1239", [900] = "881337", [950] = "4c0519" },
        }

        local tailwind_hl = {}
        vim.api.nvim_create_autocmd("ColorScheme", {
          callback = function() tailwind_hl = {} end,
        })

        hi.setup({
          highlighters = {
            hex_color = hi.gen_highlighter.hex_color({ priority = 2000 }),
            shorthand = {
              pattern = "()#%x%x%x()%f[^%x%w]",
              group = function (_, _, data)
                local match = data.full_match
                local r, g, b = match:sub(2, 2), match:sub(3, 3), match:sub(4, 4)
                local hex_color = "#" .. r .. r .. g .. g .. b .. b
                return MiniHipatterns.compute_hex_color_group(hex_color, "bg")
              end,
              extmark_opts = { priority = 2000 },
            },
            tailwind = {
              pattern = function()
                local ft = { "astro", "css", "heex", "html", "html-eex", "javascript", "javascriptreact", "rust", "svelte", "typescript", "typescriptreact", "vue" }
                if not vim.tbl_contains(ft, vim.bo.filetype) then return end
                return "%f[%w:-][%w:-]+%-[a-z%-]+%-%d+()%f[^%w:-]"
              end,
              group = function(_, _, m)
                local match = m.full_match
                local color, shade = match:match("[%w-]+%-([a-z%-]+)%-(%d+)")
                shade = tonumber(shade)
                local bg = vim.tbl_get(colors, color, shade)
                if bg then
                  local hl = "MiniHipatternsTailwind" .. color .. shade
                  if not tailwind_hl[hl] then
                    tailwind_hl[hl] = true
                    local bg_shade = shade == 500 and 950 or shade < 500 and 900 or 100
                    local fg = vim.tbl_get(colors, color, bg_shade)
                    vim.api.nvim_set_hl(0, hl, { bg = "#" .. bg, fg = "#" .. fg })
                  end
                  return hl
                end
              end,
              extmark_opts = { priority = 2000 },
            },
          },
        })
      '';
    };

    "octo" = {
      package = pkgs.vimPlugins.octo-nvim;
      event = ["BufReadPost" "BufNewFile"];
      setupModule = "octo";
      setupOpts = {
        enable_builtin = true;
        default_to_projects_v2 = true;
        default_merge_method = "squash";
        picker = "snacks";
      };
      keymaps = [
        {
          key = "<leader>gi";
          mode = "n";
          desc = "List Issues (Octo)";
          action = "<cmd>Octo issue list<cr>";
        }
        {
          key = "<leader>gI";
          mode = "n";
          desc = "Search Issues (Octo)";
          action = "<cmd>Octo issue search<cr>";
        }
        {
          key = "<leader>gp";
          mode = "n";
          desc = "List PRs (Octo)";
          action = "<cmd>Octo pr list<cr>";
        }
        {
          key = "<leader>gP";
          mode = "n";
          desc = "Search PRs (Octo)";
          action = "<cmd>Octo pr search<cr>";
        }
        {
          key = "<leader>gr";
          mode = "n";
          desc = "List Repos (Octo)";
          action = "<cmd>Octo repo list<cr>";
        }
        {
          key = "<leader>gS";
          mode = "n";
          desc = "Search (Octo)";
          action = "<cmd>Octo search<cr>";
        }
      ];
      extraLuaAfter = ''
        vim.treesitter.language.register("markdown", "octo")
        vim.api.nvim_create_autocmd("ExitPre", {
          group = vim.api.nvim_create_augroup("octo_exit_pre", { clear = true }),
          callback = function(ev)
            local keep = { "octo" }
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              local buf = vim.api.nvim_win_get_buf(win)
              if vim.tbl_contains(keep, vim.bo[buf].filetype) then
                vim.bo[buf].buftype = ""
              end
            end
          end,
        })
      '';
    };

    "kulala" = {
      package = pkgs.vimPlugins.kulala-nvim;
      setupModule = "kulala";
      filetype = ["http" "rest"];
      keymaps = [
        {
          key = "<leader>Rb";
          mode = "n";
          desc = "Open scratchpad";
          action = "function() require('kulala').scratchpad() end";
          lua = true;
        }
        {
          key = "<leader>Rc";
          mode = "n";
          desc = "Copy as cURL";
          action = "function() require('kulala').copy() end";
          lua = true;
        }
        {
          key = "<leader>RC";
          mode = "n";
          desc = "Paste from curl";
          action = "function() require('kulala').from_curl() end";
          lua = true;
        }
        {
          key = "<leader>Re";
          mode = "n";
          desc = "Set environment";
          action = "function() require('kulala').set_selected_env() end";
          lua = true;
        }
        {
          key = "<leader>Rg";
          mode = "n";
          desc = "Download GraphQL schema";
          action = "function() require('kulala').download_graphql_schema() end";
          lua = true;
        }
        {
          key = "<leader>Ri";
          mode = "n";
          desc = "Inspect current request";
          action = "function() require('kulala').inspect() end";
          lua = true;
        }
        {
          key = "<leader>Rn";
          mode = "n";
          desc = "Jump to next request";
          action = "function() require('kulala').jump_next() end";
          lua = true;
        }
        {
          key = "<leader>Rp";
          mode = "n";
          desc = "Jump to previous request";
          action = "function() require('kulala').jump_prev() end";
          lua = true;
        }
        {
          key = "<leader>Rq";
          mode = "n";
          desc = "Close window";
          action = "function() require('kulala').close() end";
          lua = true;
        }
        {
          key = "<leader>Rr";
          mode = "n";
          desc = "Replay the last request";
          action = "function() require('kulala').replay() end";
          lua = true;
        }
        {
          key = "<leader>Rs";
          mode = "n";
          desc = "Send the request";
          action = "function() require('kulala').run() end";
          lua = true;
        }
        {
          key = "<leader>RS";
          mode = "n";
          desc = "Show stats";
          action = "function() require('kulala').show_stats() end";
          lua = true;
        }
        {
          key = "<leader>Rt";
          mode = "n";
          desc = "Toggle headers/body";
          action = "function() require('kulala').toggle_view() end";
          lua = true;
        }
      ];
    };
  };
}
