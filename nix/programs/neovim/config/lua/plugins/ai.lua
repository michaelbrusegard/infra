return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.copilot-chat' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    opts = {
      model = 'claude-3.7-sonnet',
      show_help = false,
      auto_insert_mode = false,
      separator = '───',
    },
    config = function(_, opts)
      local chat = require('CopilotChat')
      vim.api.nvim_create_autocmd('BufEnter', {
        pattern = 'copilot-chat',
        callback = function()
          vim.opt_local.relativenumber = false
          vim.opt_local.number = false
          vim.keymap.set('n', '<C-s>', '<cmd>CopilotChatStop<cr>', { buffer = true })
        end,
      })

      chat.setup(opts)
    end,
  },
}
