return {
  {
    'mistweaverco/kulala.nvim',
    ft = 'http',
    keys = {
      { '<leader>r', '', desc = '+rest' },
      { '<leader>rs', "<cmd>lua require('kulala').run()<cr>", desc = 'Send the request' },
      { '<leader>rt', "<cmd>lua require('kulala').toggle_view()<cr>", desc = 'Toggle headers/body' },
      { '<leader>rp', "<cmd>lua require('kulala').jump_prev()<cr>", desc = 'Jump to previous request' },
      { '<leader>rn', "<cmd>lua require('kulala').jump_next()<cr>", desc = 'Jump to next request' },
    },
    opts = {},
  },
}
