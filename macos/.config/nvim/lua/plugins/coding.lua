return {
  -- Auto completion
  {
    -- "hrsh7th/nvim-cmp",
    -- "xzbdmw/nvim-cmp",
    -- branch = "dynamic",
    'yioneko/nvim-cmp',
    branch = 'perf',
    version = false,
    event = 'InsertEnter',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
    },
    opts = function()
      vim.api.nvim_set_hl(0, 'CmpGhostText', { link = 'Comment', default = true })
      local cmp = require('cmp')
      local defaults = require('cmp.config.default')()
      return {
        auto_brackets = {},
        performance = {
          debounce = 0,
          throttle = 0,
        },
        completion = {
          completeopt = 'menu,menuone,noinsert',
        },
        preselect = cmp.PreselectMode.Item or cmp.PreselectMode.None,
        mapping = cmp.mapping.preset.insert {
          ['<c-b>'] = cmp.mapping.scroll_docs(-4),
          ['<c-f>'] = cmp.mapping.scroll_docs(4),
          ['<c-space>'] = cmp.mapping.complete(),
          ['<c-y>'] = require('util.coding').confirm { select = true },
          ['<s-cr>'] = require('util.coding').confirm { behavior = cmp.ConfirmBehavior.Replace },
          ['<c-cr>'] = function(fallback)
            cmp.abort()
            fallback()
          end,
        },
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'path' },
        }, {
          { name = 'buffer' },
        }),
        formatting = {
          format = function(_, item)
            local icons = {
              Array = ' ',
              Boolean = '󰨙 ',
              Class = ' ',
              Codeium = '󰘦 ',
              Color = ' ',
              Control = ' ',
              Collapsed = ' ',
              Constant = '󰏿 ',
              Constructor = ' ',
              Copilot = ' ',
              Enum = ' ',
              EnumMember = ' ',
              Event = ' ',
              Field = ' ',
              File = ' ',
              Folder = ' ',
              Function = '󰊕 ',
              Interface = ' ',
              Key = ' ',
              Keyword = ' ',
              Method = '󰊕 ',
              Module = ' ',
              Namespace = '󰦮 ',
              Null = ' ',
              Number = '󰎠 ',
              Object = ' ',
              Operator = ' ',
              Package = ' ',
              Property = ' ',
              Reference = ' ',
              Snippet = ' ',
              String = ' ',
              Struct = '󰆼 ',
              TabNine = '󰏚 ',
              Text = ' ',
              TypeParameter = ' ',
              Unit = ' ',
              Value = ' ',
              Variable = '󰀫 ',
            }
            if icons[item.kind] then
              item.kind = icons[item.kind] .. item.kind
            end

            local widths = {
              abbr = 40,
              menu = 30,
            }

            for key, width in pairs(widths) do
              if item[key] and vim.fn.strdisplaywidth(item[key]) > width then
                item[key] = vim.fn.strcharpart(item[key], 0, width - 1) .. '…'
              end
            end

            return item
          end,
        },
        window = {
          completion = cmp.config.window.bordered {
            border = 'none',
            scrollbar = false,
          },
        },
        experimental = {
          ghost_text = {
            hl_group = 'CmpGhostText',
          },
        },
        sorting = defaults.sorting,
      }
    end,
    config = function(_, opts)
      require('util.coding').setup(opts)
    end,
  },
  -- Snippets
  {
    'nvim-cmp',
    dependencies = {
      {
        'garymjr/nvim-snippets',
        opts = {
          friendly_snippets = true,
        },
        dependencies = { 'rafamadriz/friendly-snippets' },
      },
    },
    opts = function(_, opts)
      opts.snippet = {
        expand = function(item)
          return require('util.coding').expand(item.body)
        end,
      }
      table.insert(opts.sources, { name = 'snippets' })
    end,
    keys = {
      {
        '<tab>',
        function()
          return vim.snippet.active { direction = 1 } and '<cmd>lua vim.snippet.jump(1)<cr>' or '<tab>'
        end,
        expr = true,
        silent = true,
        mode = { 'i', 's' },
      },
      {
        '<s-tab>',
        function()
          return vim.snippet.active { direction = -1 } and '<cmd>lua vim.snippet.jump(-1)<cr>' or '<s-tab>'
        end,
        expr = true,
        silent = true,
        mode = { 'i', 's' },
      },
    },
  },
  -- Commandline completions and search
  {
    'hrsh7th/cmp-cmdline',
    event = 'CmdlineEnter',
    config = function()
      local cmp = require('cmp')
      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = 'path' },
        }, {
          { name = 'cmdline' },
        }),
        matching = { disallow_symbol_nonprefix_matching = false },
      })
      cmp.setup.cmdline({ '/', '?' }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = 'buffer' },
        },
      })
    end,
  },
  -- Auto pairs
  {
    'echasnovski/mini.pairs',
    event = 'VeryLazy',
    opts = {
      modes = { insert = true, command = true, terminal = false },
      skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
      skip_ts = { 'string' },
      skip_unbalanced = true,
      markdown = true,
    },
    config = function(_, opts)
      require('util.coding').pairs(opts)
    end,
  },
  -- Add surround keymaps
  {
    'echasnovski/mini.surround',
    event = 'VeryLazy',
    version = false,
    keys = function(_, keys)
      -- Populate the keys based on the user's options
      local opts = require('util.lazy').opts('mini.surround')
      local mappings = {
        { opts.mappings.add, desc = 'Add Surrounding', mode = { 'n', 'v' } },
        { opts.mappings.delete, desc = 'Delete Surrounding' },
        { opts.mappings.find, desc = 'Find Right Surrounding' },
        { opts.mappings.find_left, desc = 'Find Left Surrounding' },
        { opts.mappings.highlight, desc = 'Highlight Surrounding' },
        { opts.mappings.replace, desc = 'Replace Surrounding' },
        { opts.mappings.update_n_lines, desc = 'Update `MiniSurround.config.n_lines`' },
      }
      mappings = vim.tbl_filter(function(m)
        return m[1] and #m[1] > 0
      end, mappings)
      return vim.list_extend(mappings, keys)
    end,
    opts = {
      mappings = {
        add = 'gsa',
        delete = 'gsd',
        find = 'gsf',
        find_left = 'gsF',
        highlight = 'gsh',
        replace = 'gsr',
        update_n_lines = 'gsn',
      },
    },
  },
  -- Better text-objects
  {
    'echasnovski/mini.ai',
    event = 'VeryLazy',
    opts = function()
      local ai = require('mini.ai')
      return {
        n_lines = 500,
        custom_textobjects = {
          o = ai.gen_spec.treesitter {
            a = { '@block.outer', '@conditional.outer', '@loop.outer' },
            i = { '@block.inner', '@conditional.inner', '@loop.inner' },
          },
          f = ai.gen_spec.treesitter { a = '@function.outer', i = '@function.inner' },
          c = ai.gen_spec.treesitter { a = '@class.outer', i = '@class.inner' },
          t = { '<([%p%w]-)%f[^<%w][^<>]->.-</%1>', '^<.->().*()</[^/]->$' },
          d = { '%f[%d]%d+' },
          e = {
            {
              '%u[%l%d]+%f[^%l%d]',
              '%f[%S][%l%d]+%f[^%l%d]',
              '%f[%P][%l%d]+%f[^%l%d]',
              '^[%l%d]+%f[^%l%d]',
            },
            '^().*()$',
          },
          i = require('util.coding').ai_indent,
          g = require('util.coding').ai_buffer,
          u = ai.gen_spec.function_call(),
          U = ai.gen_spec.function_call { name_pattern = '[%w_]' },
          n = ai.gen_spec.treesitter { a = '@code_cell.outer', i = '@code_cell.inner' },
        },
      }
    end,
    config = function(_, opts)
      require('mini.ai').setup(opts)
      require('util.lazy').on_load('which-key.nvim', function()
        vim.schedule(function()
          require('util.coding').ai_whichkey(opts)
        end)
      end)
    end,
  },
  -- Comments
  {
    'folke/ts-comments.nvim',
    event = 'VeryLazy',
    opts = {},
  },
  -- Better config dev behavior
  {
    'folke/lazydev.nvim',
    depdendencies = {
      'justinsgithub/wezterm-types',
    },
    ft = 'lua',
    cmd = 'LazyDev',
    opts = {
      library = {
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
        { path = 'wezterm-types', mods = { 'wezterm' } },
      },
    },
  },
  { 'Bilal2453/luvit-meta', lazy = true },
  {
    'nvim-cmp',
    opts = function(_, opts)
      table.insert(opts.sources, { name = 'lazydev', group_index = 0 })
    end,
  },
  -- Neogen
  {
    'danymat/neogen',
    cmd = 'Neogen',
    keys = {
      {
        '<leader>cn',
        function()
          require('neogen').generate()
        end,
        desc = 'Generate Annotations',
      },
    },
    opts = {
      snippet_engine = 'nvim',
    },
  },
  -- Copilot cmp source
  {
    'nvim-cmp',
    dependencies = {
      {
        'zbirenbaum/copilot-cmp',
        dependencies = { 'copilot.lua' },
        opts = {},
        config = function(_, opts)
          local copilot_cmp = require('copilot_cmp')
          copilot_cmp.setup(opts)
          -- Attach cmp source whenever copilot attaches
          -- Fixes lazy-loading issues with the copilot cmp source
          vim.api.nvim_create_autocmd('LspAttach', {
            callback = function(event)
              local client = vim.lsp.get_client_by_id(event.data.client_id)
              if client and client.name == 'copilot' then
                copilot_cmp._on_insert_enter {}
              end
            end,
          })
        end,
      },
    },
    opts = function(_, opts)
      table.insert(opts.sources, 1, {
        name = 'copilot',
        group_index = 1,
        priority = 100,
      })
    end,
  },
  -- Git source
  {
    'nvim-cmp',
    dependencies = {
      { 'petertriho/cmp-git', opts = {} },
    },
    opts = function(_, opts)
      table.insert(opts.sources, { name = 'git' })
    end,
  },
  -- Sql source
  {
    'nvim-cmp',
    dependencies = {
      {
        'MattiasMTS/cmp-dbee',
        dependencies = {
          { 'kndndrj/nvim-dbee' },
        },
        ft = 'sql',
        opts = {},
      },
    },
    opts = function(_, opts)
      table.insert(opts.sources, { name = 'dbee' })
    end,
  },
  -- TailwindCSS colorizer
  {
    'nvim-cmp',
    dependencies = {
      { 'roobert/tailwindcss-colorizer-cmp.nvim', opts = {} },
    },
    opts = function(_, opts)
      local format_kinds = opts.formatting.format
      opts.formatting.format = function(entry, item)
        format_kinds(entry, item) -- add icons
        return require('tailwindcss-colorizer-cmp').formatter(entry, item)
      end
    end,
  },
  -- Rust crates source
  {
    'nvim-cmp',
    dependencies = {
      {
        'Saecki/crates.nvim',
        event = { 'BufRead Cargo.toml' },
        opts = {
          completion = {
            cmp = { enabled = true },
          },
        },
      },
    },
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      table.insert(opts.sources, { name = 'crates' })
    end,
  },
}
