return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    dependencies = { 'stevearc/dressing.nvim' },
    opts = {
      hints = { enabled = false },
      selector = {
        provider = 'snacks',
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
