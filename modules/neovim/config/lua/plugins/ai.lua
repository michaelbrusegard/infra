return {
  {
    'NickvanDyke/opencode.nvim',
    keys = {
      {
        '<leader>aa',
        '<cmd>lua require("opencode").ask("@this: ", { submit = true })<cr>',
        mode = { 'n', 'x' },
        desc = 'Ask about this',
      },
      { '<leader>as', '<cmd>lua require("opencode").select()<cr>', mode = { 'n', 'x' }, desc = 'Select prompt' },
      { '<leader>ac', '<cmd>lua require("opencode").prompt("@this")<cr>', mode = { 'n', 'x' }, desc = 'Add this' },
      { '<leader>at', '<cmd>lua require("opencode").toggle()<cr>', desc = 'Toggle embedded' },
      { '<leader>an', '<cmd>lua require("opencode").command("session_new")<cr>', desc = 'New session' },
      { '<leader>ai', '<cmd>lua require("opencode").command("session_interrupt")<cr>', desc = 'Interrupt session' },
      { '<leader>aA', '<cmd>lua require("opencode").command("agent_cycle")<cr>', desc = 'Cycle selected agent' },
      {
        '<S-C-u>',
        '<cmd>lua require("opencode").command("messages_half_page_up")<cr>',
        desc = 'Messages half page up',
      },
      {
        '<S-C-d>',
        '<cmd>lua require("opencode").command("messages_half_page_down")<cr>',
        desc = 'Messages half page down',
      },
    },
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
