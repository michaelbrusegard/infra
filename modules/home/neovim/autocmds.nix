_: {
  programs.neovim.spec = {
    augroups = [
      {name = "Checktime";}
      {name = "HighlightYank";}
      {name = "ResizeSplits";}
      {name = "LastLoc";}
      {name = "CloseWithQ";}
      {name = "ManUnlisted";}
      {name = "WrapSpell";}
      {name = "JsonConceal";}
      {name = "AutoCreateDir";}
      {name = "RandomTempFile";}
    ];

    autocmds = [
      # Check if we need to reload the file when it changed
      {
        event = ["FocusGained" "TermClose" "TermLeave"];
        group = "Checktime";
        callback = ''
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
        group = "HighlightYank";
        callback = ''
          function()
            (vim.hl or vim.highlight).on_yank()
          end
        '';
      }

      # Resize splits if window got resized
      {
        event = ["VimResized"];
        group = "ResizeSplits";
        callback = ''
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
        group = "LastLoc";
        callback = ''
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
        group = "CloseWithQ";
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
        callback = ''
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
        group = "ManUnlisted";
        pattern = ["man"];
        callback = ''
          function(event)
            vim.bo[event.buf].buflisted = false
          end
        '';
      }

      # Wrap and check for spell in text filetypes
      {
        event = ["FileType"];
        group = "WrapSpell";
        pattern = ["text" "plaintex" "typst" "gitcommit" "markdown"];
        callback = ''
          function()
            vim.opt_local.wrap = true
            vim.opt_local.spell = true
          end
        '';
      }

      # Fix conceallevel for json files
      {
        event = ["FileType"];
        group = "JsonConceal";
        pattern = ["json" "jsonc" "json5"];
        callback = ''
          function()
            vim.opt_local.conceallevel = 0
          end
        '';
      }

      # Auto create dir when saving a file
      {
        event = ["BufWritePre"];
        group = "AutoCreateDir";
        callback = ''
          function(event)
            if event.match:match("^%w%w+:[\\/][\\/]") then
              return
            end
            local file = vim.uv.fs_realpath(event.match) or event.match
            vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
          end
        '';
      }

      # Open random temp file on startup if no file is specified
      {
        event = ["VimEnter"];
        group = "RandomTempFile";
        callback = ''
          function()
            if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" and vim.bo.buftype == "" then
              local fname = "/tmp/scratch-" .. os.date("%Y%m%d-%H%M%S") .. ".md"
              vim.cmd("edit " .. fname)
            end
          end
        '';
      }
    ];
  };
}
