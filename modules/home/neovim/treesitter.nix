{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec = {
    treesitter = {
      setupOpts = {
        highlight = {
          enable = true;
          additional_vim_regex_highlighting = false;
        };
        indent = {
          enable = true;
        };
      };
      augroups = [
        {name = "UserTreesitter";}
      ];
      autocmds = [
        {
          event = "FileType";
          pattern = "*";
          group = "UserTreesitter";
          callback = ''
            function(args)
              local lang = vim.treesitter.language.get_lang(args.match)
              if not pcall(vim.treesitter.get_parser, args.buf, lang) then return end
              pcall(vim.treesitter.start, args.buf)
              local ok, query = pcall(vim.treesitter.query.get, lang, "indents")
              if ok and query then
                vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
              end
              ok, query = pcall(vim.treesitter.query.get, lang, "folds")
              if ok and query then
                vim.wo.foldmethod = "expr"
                vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
              end
            end
          '';
        }
      ];
      grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        bash
        c
        diff
        lua
        luadoc
        luap
        printf
        query
        regex
        vim
        vimdoc
      ];
    };

    plugins = {
      "nvim-ts-autotag" = {
        package = pkgs.vimPlugins.nvim-ts-autotag;
        after = "nvim-treesitter";
        setupModule = "nvim-ts-autotag";
        setupOpts = {
          opts = {
            enable_close = true;
            enable_rename = true;
            enable_close_on_slash = true;
          };
        };
      };

      "nvim-treesitter-textobjects" = {
        package = pkgs.vimPlugins.nvim-treesitter-textobjects;
        after = "nvim-treesitter";
        setupModule = "nvim-treesitter-textobjects";
        setupOpts = {
          select = {
            enable = true;
            lookahead = true;
            keymaps = lib.generators.mkLuaInline ''
              {
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",
                ["ac"] = "@class.outer",
                ["ic"] = "@class.inner",
                ["aa"] = "@parameter.outer",
                ["ia"] = "@parameter.inner"
              }
            '';
          };
          move = {
            enable = true;
            set_jumps = true;
          };
        };
        extraLuaAfter = ''
          local group = vim.api.nvim_create_augroup("UserTreesitterTextobjects", { clear = true })

          local function attach_textobjects(buf)
            if vim.b[buf].textobjects_attached or vim.wo.diff then
              return
            end

            local ok, parser = pcall(vim.treesitter.get_parser, buf)
            if not ok or not parser then
              return
            end

            local has_textobjects = pcall(function()
              return vim.treesitter.query.get(parser:lang(), "textobjects") ~= nil
            end)

            if not has_textobjects then
              return
            end

            vim.b[buf].textobjects_attached = true

            local move = require("nvim-treesitter-textobjects.move")

            local function map(mappings, fn_name, desc_fn)
              for key, query in pairs(mappings) do
                if vim.wo.diff and (key:find("[cC]") or query:find("class")) then
                  goto continue
                end

                vim.keymap.set({ "n", "x", "o" }, key, function()
                  move[fn_name](query, "textobjects")
                end, {
                  buffer = buf,
                  desc = desc_fn(query),
                  silent = true,
                  noremap = true,
                })

                ::continue::
              end
            end

            map({
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]a"] = "@parameter.inner",
            }, "goto_next_start", function(q)
              return "Next " .. q:gsub("@", ""):gsub("%.outer", ""):gsub("%.inner", "")
            end)

            map({
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]A"] = "@parameter.inner",
            }, "goto_next_end", function(q)
              return "Next " .. q:gsub("@", ""):gsub("%.outer", ""):gsub("%.inner", "") .. " End"
            end)

            map({
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[a"] = "@parameter.inner",
            }, "goto_previous_start", function(q)
              return "Prev " .. q:gsub("@", ""):gsub("%.outer", ""):gsub("%.inner", "")
            end)

            map({
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[A"] = "@parameter.inner",
            }, "goto_previous_end", function(q)
              return "Prev " .. q:gsub("@", ""):gsub("%.outer", ""):gsub("%.inner", "") .. " End"
            end)
          end

          vim.api.nvim_create_autocmd("FileType", {
            group = group,
            callback = function(ev)
              attach_textobjects(ev.buf)
            end,
          })

          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) then
              attach_textobjects(buf)
            end
          end
        '';
      };
    };
  };
}
