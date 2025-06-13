return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    dependencies = { 'stevearc/dressing.nvim' },
    opts = {
      hints = { enabled = false },
      provider = 'copilot-gpt',
      gemini = {
        hide_in_model_selector = true,
        max_tokens = 1000000,
      },
      copilot = {
        hide_in_model_selector = true,
        max_tokens = 1000000,
        extra_request_body = {
          temperature = 0.5,
          max_tokens = 1000000,
        },
      },
      cohere = {
        hide_in_model_selector = true,
      },
      openai = {
        hide_in_model_selector = true,
      },
      ['openai-gpt-4o-mini'] = {
        hide_in_model_selector = true,
      },
      bedrock = {
        hide_in_model_selector = true,
      },
      ['bedrock-claude-3.7-sonnet'] = {
        hide_in_model_selector = true,
      },
      claude = {
        hide_in_model_selector = true,
      },
      ['claude-opus'] = {
        hide_in_model_selector = true,
      },
      ['claude-haiku'] = {
        hide_in_model_selector = true,
      },
      vertex = {
        hide_in_model_selector = true,
      },
      vertex_claude = {
        hide_in_model_selector = true,
      },
      aihubmix = {
        hide_in_model_selector = true,
      },
      ['aihubmix-claude'] = {
        hide_in_model_selector = true,
      },
      vendors = {
        ['copilot-gpt'] = {
          __inherited_from = 'copilot',
          model = 'gpt-4.1',
        },
        ['copilot-claude'] = {
          __inherited_from = 'copilot',
          model = 'claude-sonnet-4',
        },
        ['copilot-gemini'] = {
          __inherited_from = 'copilot',
          model = 'gemini-2.5-pro',
        },
        ['gemini-api'] = {
          __inherited_from = 'gemini',
          model = 'gemini-2.5-pro-preview-06-05',
        },
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
