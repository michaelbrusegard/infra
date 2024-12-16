return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.copilot-chat' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    opts = {
      model = 'claude-3.5-sonnet',
      show_help = false,
      auto_insert_mode = false,
      separator = '───',
    },
  },
}
