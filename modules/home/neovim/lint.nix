_: {
  programs.nvf.settings.vim = {
    diagnostics.nvim-lint = {
      enable = true;
      lint_after_save = true;
      linters_by_ft = {
        fish = ["fish"];
      };
      lint_function = {
        _type = "lua-inline";
        expr = ''
          function(buf)
            local lint = require("lint")
            local names = lint._resolve_linter_by_ft(vim.bo.filetype)

            -- Create a copy of the names table
            names = vim.list_extend({}, names)

            -- Add fallback linters if none found for filetype
            if #names == 0 then
              vim.list_extend(names, lint.linters_by_ft["_"] or {})
            end

            -- Add global linters (*)
            vim.list_extend(names, lint.linters_by_ft["*"] or {})

            -- Filter out linters that don't exist
            local ctx = { filename = vim.api.nvim_buf_get_name(0) }
            ctx.dirname = vim.fn.fnamemodify(ctx.filename, ":h")
            names = vim.tbl_filter(function(name)
              local linter = lint.linters[name]
              if not linter then
                -- Silent ignore if linter doesn't exist to avoid noise
                return false
              end
              -- LazyVim style condition check if you add custom linters with conditions later
              return not (type(linter) == "table" and linter.condition and not linter.condition(ctx))
            end, names)

            if #names > 0 then
              lint.try_lint(names)
            end
          end
        '';
      };
    };
    luaConfigRC.nvim-lint-extras = ''
      local lint_group = vim.api.nvim_create_augroup("nvim-lint-extras", { clear = true })

      local function debounce(ms, fn)
        local timer = vim.uv.new_timer()
        return function(...)
          local argv = { ... }
          timer:start(ms, 0, function()
            timer:stop()
            vim.schedule_wrap(fn)(unpack(argv))
          end)
        end
      end

      local do_lint = debounce(100, function()
        -- nvf_lint is the name of the function defined in diagnostics.nvim-lint.lint_function
        if _G.nvf_lint then
          _G.nvf_lint(vim.api.nvim_get_current_buf())
        end
      end)

      vim.api.nvim_create_autocmd({ "BufReadPost", "InsertLeave" }, {
        group = lint_group,
        callback = do_lint,
      })
    '';
  };
}
