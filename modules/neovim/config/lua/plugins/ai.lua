return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    dependencies = { 'stevearc/dressing.nvim' },
    opts = {
      hints = { enabled = false },
      provider = 'copilot',
      gemini = {
        model = 'gemini-2.5-pro-preview-05-06',
        max_tokens = 1000000,
        disable_tools = true,
      },
      copilot = {
        model = 'claude-3.5-sonnet',
        max_tokens = 200000,
        disable_tools = true,
      },
      selector = {
        provider = 'snacks',
      },
    },
    build = 'make',
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
