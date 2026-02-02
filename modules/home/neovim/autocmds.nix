{lib, ...}: {
  programs.nvf.settings.vim.augroups = [
    {name = "checktime";}
    {name = "highlight_yank";}
    {name = "resize_splits";}
    {name = "last_loc";}
    {name = "close_with_q";}
    {name = "man_unlisted";}
    {name = "wrap_spell";}
    {name = "json_conceal";}
    {name = "auto_create_dir";}
  ];

  programs.nvf.settings.vim.autocmds = [
    # Check if we need to reload the file when it changed
    {
      event = ["FocusGained" "TermClose" "TermLeave"];
      group = "checktime";
      callback = lib.generators.mkLuaInline ''
        function()
          if vim.o.buftype ~= "nofile" then
            vim.cmd("checktime")
          end
        end
      '';
    }

    # Highlight on yank
    {
      event = ["TextYankPost"];
      group = "highlight_yank";
      callback = lib.generators.mkLuaInline ''
        function()
          (vim.hl or vim.highlight).on_yank()
        end
      '';
    }

    # Resize splits if window got resized
    {
      event = ["VimResized"];
      group = "resize_splits";
      callback = lib.generators.mkLuaInline ''
        function()
          local current_tab = vim.fn.tabpagenr()
          vim.cmd("tabdo wincmd =")
          vim.cmd("tabnext " .. current_tab)
        end
      '';
    }

    # Go to last loc when opening a buffer
    {
      event = ["BufReadPost"];
      group = "last_loc";
      callback = lib.generators.mkLuaInline ''
        function(event)
          local exclude = { "gitcommit" }
          local buf = event.buf
          if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].last_loc then
            return
          end
          vim.b[buf].last_loc = true
          local mark = vim.api.nvim_buf_get_mark(buf, '"')
          local lcount = vim.api.nvim_buf_line_count(buf)
          if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end
      '';
    }

    # Close some filetypes with <q>
    {
      event = ["FileType"];
      group = "close_with_q";
      pattern = [
        "PlenaryTestPopup"
        "checkhealth"
        "dbout"
        "gitsigns-blame"
        "grug-far"
        "help"
        "lspinfo"
        "neotest-output"
        "neotest-output-panel"
        "neotest-summary"
        "notify"
        "qf"
        "startuptime"
        "tsplayground"
      ];
      callback = lib.generators.mkLuaInline ''
        function(event)
          vim.bo[event.buf].buflisted = false
          vim.schedule(function()
            vim.keymap.set("n", "q", function()
              vim.cmd("close")
              pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
            end, {
              buffer = event.buf,
              silent = true,
              desc = "Quit buffer",
            })
          end)
        end
      '';
    }

    # Make it easier to close man-files when opened inline
    {
      event = ["FileType"];
      group = "man_unlisted";
      pattern = ["man"];
      callback = lib.generators.mkLuaInline ''
        function(event)
          vim.bo[event.buf].buflisted = false
        end
      '';
    }

    # Wrap and check for spell in text filetypes
    {
      event = ["FileType"];
      group = "wrap_spell";
      pattern = ["text" "plaintex" "typst" "gitcommit" "markdown"];
      callback = lib.generators.mkLuaInline ''
        function()
          vim.opt_local.wrap = true
          vim.opt_local.spell = true
        end
      '';
    }

    # Fix conceallevel for json files
    {
      event = ["FileType"];
      group = "json_conceal";
      pattern = ["json" "jsonc" "json5"];
      callback = lib.generators.mkLuaInline ''
        function()
          vim.opt_local.conceallevel = 0
        end
      '';
    }

    # Auto create dir when saving a file
    {
      event = ["BufWritePre"];
      group = "auto_create_dir";
      callback = lib.generators.mkLuaInline ''
        function(event)
          if event.match:match("^%w%w+:[\\/][\\/]") then
            return
          end
          local file = vim.uv.fs_realpath(event.match) or event.match
          vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
        end
      '';
    }
  ];
}
