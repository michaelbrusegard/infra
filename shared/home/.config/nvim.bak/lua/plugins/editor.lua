return {
  -- Search/replace in multiple files
  {
    'MagicDuck/grug-far.nvim',
    opts = {
      headerMaxWidth = 80,
      disableBufferLineNumbers = false,
    },
    cmd = 'GrugFar',
    keys = {
      {
        '<leader>sr',
        function()
          local is_visual = vim.fn.mode():lower():find('v')
          if is_visual then -- needed to make visual selection work
            vim.cmd([[normal! v]])
          end
          local grug = require('grug-far')
          local ext = vim.bo.buftype == '' and vim.fn.expand('%:e')
          local filesFilter = ext and ext ~= '' and '*.' .. ext or nil;
          (is_visual and grug.with_visual_selection or grug.grug_far)({
            prefills = { filesFilter = filesFilter },
          })
        end,
        mode = { 'n', 'v' },
        desc = 'Search and Replace',
      },
    },
  },
  -- Flash enhances the built-in search functionality by showing labels
  -- at the end of each match, letting you quickly jump to a specific
  -- location.
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    opts = {
      modes = {
        char = {
          enabled = false,
        },
      },
    },
    keys = {
      { 's', mode = { 'n', 'x', 'o' }, "<cmd>lua require('flash').jump()<cr>", desc = 'Flash' },
      { 'S', mode = { 'n', 'x', 'o' }, "<cmd>lua require('flash').treesitter()<cr>", desc = 'Flash Treesitter' },
      {
        'R',
        mode = { 'o', 'x' },
        "<cmd>lua function() require('flash').treesitter_search()<cr>",
        desc = 'Treesitter Search',
      },
      { '<c-s>', mode = { 'c' }, "<cmd>lua require('flash').toggle()<cr>", desc = 'Toggle Flash Search' },
    },
  },
  -- which-key helps you remember key bindings by showing a popup
  -- with the active keybindings of the command you started typing.
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts_extend = { 'spec' },
    opts = {
      defaults = {},
      spec = {
        {
          mode = { 'n', 'v' },
          { '<leader>c', group = 'code' },
          { '<leader>f', group = 'file/find' },
          { '<leader>g', group = 'git' },
          { '<leader>s', group = 'search/screenshot' },
          { '<leader>n', group = 'notebook' },
          { '<leader>m', group = 'snow' },
          { '<leader>l', group = 'log/lib', icon = { icon = '󰙵 ', color = 'cyan' } },
          { '<leader>x', group = 'trouble', icon = { icon = '󱖫 ', color = 'green' } },
          { '[', group = 'prev' },
          { ']', group = 'next' },
          { 'g', group = 'goto' },
          { 'gs', group = 'surround' },
          { 'z', group = 'fold' },
          {
            '<leader>b',
            group = 'buffer',
            expand = function()
              return require('which-key.extras').expand.buf()
            end,
          },
          {
            '<leader>w',
            group = 'windows',
            proxy = '<c-w>',
            expand = function()
              return require('which-key.extras').expand.win()
            end,
          },
        },
      },
    },
    config = function(_, opts)
      local wk = require('which-key')
      wk.setup(opts)
    end,
  },
  -- Show git signs in the sign column
  {
    'lewis6991/gitsigns.nvim',
    event = 'LazyFile',
    opts = {
      signs = {
        add = { text = '▎' },
        change = { text = '▎' },
        delete = { text = '' },
        topdelete = { text = '' },
        changedelete = { text = '▎' },
        untracked = { text = '▎' },
      },
      signs_staged = {
        add = { text = '▎' },
        change = { text = '▎' },
        delete = { text = '' },
        topdelete = { text = '' },
        changedelete = { text = '▎' },
      },
      on_attach = function(buffer)
        local gs = package.loaded.gitsigns

        vim.keymap.set('n', ']g', function()
          if vim.wo.diff then
            vim.cmd.normal({ ']c', bang = true })
          else
            gs.nav_hunk('next')
          end
        end, { buffer = buffer, desc = 'Git Next Hunk' })
        vim.keymap.set('n', '[g', function()
          if vim.wo.diff then
            vim.cmd.normal({ '[c', bang = true })
          else
            gs.nav_hunk('prev')
          end
        end, { buffer = buffer, desc = 'Git Prev Hunk' })
        vim.keymap.set(
          'n',
          ']G',
          "<cmd>lua require('gitsigns').nav_hunk('last')<cr>",
          { buffer = buffer, desc = 'Git Last Hunk' }
        )
        vim.keymap.set(
          'n',
          '[G',
          "<cmd>lua require('gitsigns').nav_hunk('first')<cr>",
          { buffer = buffer, desc = 'Git First Hunk' }
        )
        vim.keymap.set(
          { 'n', 'v' },
          '<leader>gs',
          '<cmd>Gitsigns stage_hunk<cr>',
          { buffer = buffer, desc = 'Git Stage Hunk' }
        )
        vim.keymap.set(
          { 'n', 'v' },
          '<leader>gr',
          '<cmd>Gitsigns reset_hunk<cr>',
          { buffer = buffer, desc = 'Git Reset Hunk' }
        )
        vim.keymap.set('n', '<leader>gS', gs.stage_buffer, { buffer = buffer, desc = 'Git Stage Buffer' })
        vim.keymap.set('n', '<leader>gu', gs.undo_stage_hunk, { buffer = buffer, desc = 'Git Undo Stage Hunk' })
        vim.keymap.set('n', '<leader>gR', gs.reset_buffer, { buffer = buffer, desc = 'Git Reset Buffer' })
        vim.keymap.set('n', '<leader>gp', gs.preview_hunk_inline, { buffer = buffer, desc = 'Git Preview Hunk Inline' })
        vim.keymap.set('n', '<leader>gb', gs.blame_line, { buffer = buffer, desc = 'Git Blame Line' })
        vim.keymap.set('n', '<leader>gd', gs.diffthis, { buffer = buffer, desc = 'Git Diff This' })
        vim.keymap.set(
          { 'o', 'x' },
          'ih',
          '<cmd>Gitsigns select_hunk<cr>',
          { buffer = buffer, desc = 'Git Select Hunk' }
        )
      end,
    },
  },
  -- Better diagnostics list and others
  {
    'folke/trouble.nvim',
    cmd = { 'Trouble' },
    opts = {
      modes = {
        lsp = {
          win = { position = 'right' },
        },
      },
    },
    keys = {
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', desc = 'Diagnostics' },
      { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', desc = 'Buffer Diagnostics' },
      { '<leader>cs', '<cmd>Trouble symbols toggle<cr>', desc = 'Symbols' },
      { '<leader>cS', '<cmd>Trouble lsp toggle<cr>', desc = 'LSP References' },
      { '<leader>xL', '<cmd>Trouble loclist toggle<cr>', desc = 'Location List' },
      { '<leader>xQ', '<cmd>Trouble qflist toggle<cr>', desc = 'Quickfix List' },
      {
        '[q',
        function()
          if require('trouble').is_open() then
            require('trouble').prev({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cprev)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = 'Previous Quickfix Item',
      },
      {
        ']q',
        function()
          if require('trouble').is_open() then
            require('trouble').next({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cnext)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = 'Next Quickfix Item',
      },
    },
  },
  -- Finds and lists all of the TODO, HACK, BUG, etc comment
  -- in your project and loads them into a browsable list.
  {
    'folke/todo-comments.nvim',
    cmd = { 'TodoTrouble' },
    event = 'LazyFile',
    opts = {},
    -- stylua: ignore
    keys = {
      { "]t", "<cmd>lua require('todo-comments').jump_next()<cr>", desc = "Next Todo Comment" },
      { "[t", "<cmd>lua require('todo-comments').jump_prev()<cr>", desc = "Previous Todo Comment" },
      { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Todo" },
      { "<leader>xT", "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>", desc = "Filter Todo/Fix/Fixme" },
    },
  },
  -- Move selected text
  {
    'echasnovski/mini.move',
    event = 'VeryLazy',
    version = false,
    opts = {
      mappings = {
        left = '<s-h>',
        right = '<s-l>',
        down = '<s-j>',
        up = '<s-k>',
        line_left = '',
        line_right = '',
        line_down = '',
        line_up = '',
      },
      options = {
        reindent_linewise = true,
      },
    },
  },
  -- Increment and decrement numbers, dates, and more
  {
    'monaqa/dial.nvim',
  -- stylua: ignore
  keys = {
    { "<c-a>", function() return require('util.editor').dial(true) end, expr = true, desc = "Increment", mode = {"n", "x"} },
    { "<c-x>", function() return require('util.editor').dial(false) end, expr = true, desc = "Decrement", mode = {"n", "x"} },
    { "g<c-a>", function() return require('util.editor').dial(true, true) end, expr = true, desc = "Increment", mode = {"n", "x"} },
    { "g<c-x>", function() return require('util.editor').dial(false, true) end, expr = true, desc = "Decrement", mode = {"n", "x"} },
  },
    opts = function()
      local augend = require('dial.augend')

      local logical_alias = augend.constant.new({
        elements = { '&&', '||' },
        word = false,
        cyclic = true,
      })

      local ordinal_numbers = augend.constant.new({
        -- elements through which we cycle. When we increment, we go down
        -- On decrement we go up
        elements = {
          'first',
          'second',
          'third',
          'fourth',
          'fifth',
          'sixth',
          'seventh',
          'eighth',
          'ninth',
          'tenth',
        },
        -- if true, it only matches strings with word boundary. firstDate wouldn't work for example
        word = false,
        -- do we cycle back and forth (tenth to first on increment, first to tenth on decrement).
        -- Otherwise nothing will happen when there are no further values
        cyclic = true,
      })

      local weekdays = augend.constant.new({
        elements = {
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        },
        word = true,
        cyclic = true,
      })

      local months = augend.constant.new({
        elements = {
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        },
        word = true,
        cyclic = true,
      })

      local capitalized_boolean = augend.constant.new({
        elements = {
          'True',
          'False',
        },
        word = true,
        cyclic = true,
      })

      return {
        dials_by_ft = {
          css = 'css',
          javascript = 'typescript',
          javascriptreact = 'typescript',
          json = 'json',
          lua = 'lua',
          markdown = 'markdown',
          python = 'python',
          sass = 'css',
          scss = 'css',
          typescript = 'typescript',
          typescriptreact = 'typescript',
          yaml = 'yaml',
        },
        groups = {
          default = {
            augend.integer.alias.decimal, -- nonnegative decimal number (0, 1, 2, 3, ...)
            augend.integer.alias.hex, -- nonnegative hex number  (0x01, 0x1a1f, etc.)
            augend.date.alias['%Y/%m/%d'], -- date (2022/02/19, etc.)
            ordinal_numbers,
            weekdays,
            months,
          },
          typescript = {
            augend.integer.alias.decimal, -- nonnegative and negative decimal number
            augend.constant.alias.bool, -- boolean value (true <-> false)
            logical_alias,
            augend.constant.new({ elements = { 'let', 'const' } }),
          },
          yaml = {
            augend.integer.alias.decimal, -- nonnegative and negative decimal number
            augend.constant.alias.bool, -- boolean value (true <-> false)
          },
          css = {
            augend.integer.alias.decimal, -- nonnegative and negative decimal number
            augend.hexcolor.new({
              case = 'lower',
            }),
            augend.hexcolor.new({
              case = 'upper',
            }),
          },
          markdown = {
            augend.misc.alias.markdown_header,
          },
          json = {
            augend.integer.alias.decimal, -- nonnegative and negative decimal number
            augend.semver.alias.semver, -- versioning (v1.1.2)
          },
          lua = {
            augend.integer.alias.decimal, -- nonnegative and negative decimal number
            augend.constant.alias.bool, -- boolean value (true <-> false)
            augend.constant.new({
              elements = { 'and', 'or' },
              word = true, -- if false, "sand" is incremented into "sor", "doctor" into "doctand", etc.
              cyclic = true, -- "or" is incremented into "and".
            }),
          },
          python = {
            augend.integer.alias.decimal, -- nonnegative and negative decimal number
            capitalized_boolean,
            logical_alias,
          },
        },
      }
    end,
    config = function(_, opts)
      require('dial.config').augends:register_group(opts.groups)
      vim.g.dials_by_ft = opts.dials_by_ft
    end,
  },
  -- Incremental rename
  { 'saecki/live-rename.nvim', event = 'InsertEnter' },
  -- Remove search highlights when moving
  {
    'nvimdev/hlsearch.nvim',
    event = 'BufRead',
    opts = {},
  },
  -- Set shiftwidth based on what is used in project
  {
    'nmac427/guess-indent.nvim',
    event = 'LazyFile',
    opts = {
      filetype_exclude = {
        'oil',
        'fzf',
        'mason',
        'lazy',
        'harpoon',
        'noice',
        'grug-far',
      },
    },
  },
}
