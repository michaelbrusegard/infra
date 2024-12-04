return {
  -- AI integration
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    lazy = false,
    version = false,
    opts = {
      provider = 'claude',
      auto_suggestions_provider = 'copilot',
      windows = {
        width = 50,
        sidebar_header = {
          enabled = false,
        },
        input = {
          prefix = '> ',
          height = 8,
        },
        ask = {
          start_insert = false,
          border = 'none',
        },
      },
    },
    build = 'make',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'echasnovski/mini.icons',
      {
        'HakonHarnes/img-clip.nvim',
        event = 'VeryLazy',
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            use_absolute_path = true,
          },
        },
      },
      {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
          file_types = { 'markdown', 'Avante' },
        },
        ft = { 'markdown', 'Avante' },
      },
    },
  },
  -- Copilot
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    build = ':Copilot auth',
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        help = true,
      },
    },
  },
  -- Supermaven
  {
    'supermaven-inc/supermaven-nvim',
    event = 'InsertEnter',
    build = ':SupermavenUseFree',
    opts = {
      disable_inline_completion = true,
      disable_keymaps = true,
      log_level = 'off',
    },
  },
}
