return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    dependencies = { 'stevearc/dressing.nvim' },
    opts = {
      hints = { enabled = false },
      provider = 'gemini',
      gemini = {
        model = 'gemini-2.5-pro-exp-03-25',
      },
      copilot = {
        model = 'claude-3.5-sonnet',
      },
      selector = {
        provider = 'snacks',
      },
    },
    build = 'make',
  },
  {
    'saghen/blink.cmp',
    lazy = true,
    dependencies = { 'saghen/blink.compat' },
    opts = {
      sources = {
        default = { 'avante_commands', 'avante_mentions', 'avante_files' },
        compat = {
          'avante_commands',
          'avante_mentions',
          'avante_files',
        },
        providers = {
          avante_commands = {
            name = 'avante_commands',
            module = 'blink.compat.source',
            score_offset = 90,
            opts = {},
          },
          avante_files = {
            name = 'avante_files',
            module = 'blink.compat.source',
            score_offset = 100,
            opts = {},
          },
          avante_mentions = {
            name = 'avante_mentions',
            module = 'blink.compat.source',
            score_offset = 1000,
            opts = {},
          },
        },
      },
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = function(_, ft)
      vim.list_extend(ft, { 'Avante' })
    end,
    opts = function(_, opts)
      opts.file_types = vim.list_extend(opts.file_types or {}, { 'Avante' })
    end,
  },
  {
    'folke/which-key.nvim',
    opts = {
      spec = {
        { '<leader>a', group = 'ai' },
      },
    },
  },
}
