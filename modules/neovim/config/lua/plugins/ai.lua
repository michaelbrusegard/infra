return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    dependencies = { 'stevearc/dressing.nvim' },
    opts = function()
      local opts = {
        hints = { enabled = false },
        provider = 'copilot/gpt-4.1',
        providers = {
          ['copilot/gpt-4.1'] = {
            __inherited_from = 'copilot',
            model = 'gpt-4.1',
            display_name = 'copilot/gpt-4.1',
          },
          ['copilot/claude-sonnet-4'] = {
            __inherited_from = 'copilot',
            model = 'claude-sonnet-4',
            display_name = 'copilot/claude-sonnet-4',
          },
          ['copilot/gemini-2.0-flash'] = {
            __inherited_from = 'copilot',
            model = 'gemini-2.0-flash-001',
            display_name = 'copilot/gemini-2.0-flash',
          },
          ['copilot/gemini-2.5-pro'] = {
            __inherited_from = 'copilot',
            model = 'gemini-2.5-pro',
            display_name = 'copilot/gemini-2.5-pro',
          },
          ['api/gemini-2.5-flash'] = {
            __inherited_from = 'gemini',
            model = 'gemini-2.5-flash',
            display_name = 'api/gemini-2.5-flash',
          },
          ['api/gemini-2.5-pro'] = {
            __inherited_from = 'gemini',
            model = 'gemini-2.5-pro',
            display_name = 'api/gemini-2.5-pro',
          },
        },
        selector = {
          provider = 'snacks',
        },
      }
      local hidden_models = {
        'copilot',
        'gemini',
        'openai',
        'openai-gpt-4o-mini',
        'vertex',
        'vertex_claude',
        'ollama',
      }
      for _, provider in pairs(opts.providers) do
        provider.hide_in_model_selector = false
      end

      for _, model in ipairs(hidden_models) do
        opts.providers[model] = { hide_in_model_selector = true }
      end

      return opts
    end,
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
