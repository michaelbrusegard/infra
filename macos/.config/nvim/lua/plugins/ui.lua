return {
  -- Statusline
  {
    'nvim-lualine/lualine.nvim',
    event = 'VeryLazy',
    init = function()
      vim.g.lualine_laststatus = vim.o.laststatus
      if vim.fn.argc(-1) > 0 then
        -- Set an empty statusline till lualine loads
        vim.o.statusline = ' '
      else
        -- hide the statusline on the starter page
        vim.o.laststatus = 0
      end
    end,
    opts = function()
      -- PERF: we don't need this lualine require madness 🤷
      local lualine_require = require('lualine_require')
      lualine_require.require = require

      vim.o.laststatus = vim.g.lualine_laststatus

      local opts = {
        options = {
          theme = 'auto',
          globalstatus = vim.o.laststatus == 3,
          section_separators = { left = '', right = '' },
          component_separators = { left = '', right = '' },
        },
        sections = {
          lualine_a = { { 'mode', fmt = string.lower } },
          lualine_b = {
            'branch',
            'diff',
            {
              'diagnostics',
              symbols = { error = ' ', warn = ' ', info = ' ', hint = ' ' },
            },
          },
          lualine_c = {
            require('util.ui').root_dir(),
            require('util.ui').pretty_path(),
          },
          lualine_x = {
            {
              function()
                local message = require('noice').api.statusline.mode.get()
                if not message:find('---') then
                  return message
                end
                return ''
              end,
              cond = require('noice').api.statusline.mode.has,
              color = { fg = '#fab387' },
            },
          },
        },
        extensions = { 'lazy', 'mason', 'oil', 'trouble', 'nvim-dap-ui' },
      }
      return opts
    end,
  },
  -- Indent guides for Neovim
  {
    'lukas-reineke/indent-blankline.nvim',
    event = 'LazyFile',
    opts = {
      indent = {
        char = '▏',
        tab_char = '▏',
      },
      exclude = {
        filetypes = {
          'help',
          'Trouble',
          'trouble',
          'lazy',
          'mason',
          'lazyterm',
        },
      },
    },
    main = 'ibl',
  },
  -- Line decorations
  {
    'mvllow/modes.nvim',
    event = 'LazyFile',
    -- branch = "canary",
    opts = {
      colors = {
        copy = '#f9e2af',
        delete = '#f38ba8',
        insert = '#94e2d5',
        replace = '#eba0ac',
        visual = '#cba6f7',
      },
    },
    line_opacity = 0.15,
    set_cursorline = true,
    set_number = false,
    set_signcolumn = false,
  },
  -- Notifications
  {
    'j-hui/fidget.nvim',
    event = 'VeryLazy',
    opts = {
      progress = {
        display = {
          overrides = {
            rust_analyzer = { name = 'rust-analyzer' },
            lua_ls = { name = 'lua-ls' },
          },
        },
      },
    },
  },
  -- Highly experimental plugin that completely replaces the UI for messages, cmdline and the popupmenu.
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    opts = {
      lsp = {
        progress = {
          enabled = false,
        },
        override = {
          ['cmp.entry.get_documentation'] = true,
        },
      },
      routes = {
        {
          filter = {
            any = {
              { find = '(%d+)L, (%d+)B%s+%[w%]%s*$' },
            },
          },
          view = 'fidget',
        },
      },
      views = {
        cmdline_popup = {
          position = {
            row = vim.o.lines,
            col = 10,
          },
          size = {
            width = vim.o.columns - 19,
            height = 1,
          },
          border = {
            style = 'none',
          },
          win_options = {
            winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder',
          },
        },
      },
      presets = {
        long_message_to_split = true,
        inc_rename = false,
        lsp_doc_border = false,
      },
    },
    keys = {
      {
        '<s-enter>',
        "<cmd>lua require('noice').redirect(vim.fn.getcmdline())<cr>",
        mode = 'c',
        desc = 'Redirect Cmdline',
      },
      { '<leader>lp', "<cmd>lua require('noice').cmd('last')<cr>", desc = 'Log Prev Message' },
      { '<leader>lh', "<cmd>lua require('noice').cmd('history')<cr>", desc = 'Log History' },
      {
        '<c-f>',
        function()
          if not require('noice.lsp').scroll(4) then
            return '<c-f>'
          end
        end,
        silent = true,
        expr = true,
        desc = 'Scroll Forward',
        mode = { 'i', 'n', 's' },
      },
      {
        '<c-b>',
        function()
          if not require('noice.lsp').scroll(-4) then
            return '<c-b>'
          end
        end,
        silent = true,
        expr = true,
        desc = 'Scroll Backward',
        mode = { 'i', 'n', 's' },
      },
    },
    config = function(_, opts)
      if vim.o.filetype == 'lazy' then
        vim.cmd([[messages clear]])
      end

      require('util.ui').fidgetview()

      require('noice').setup(opts)
    end,
  },
  -- UI components
  { 'MunifTanjim/nui.nvim', lazy = true },
}
