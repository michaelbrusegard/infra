return {
  {
    'neovim/nvim-lspconfig',
    opts = function()
      local keys = require('lazyvim.plugins.lsp.keymaps').get()
      keys[#keys + 1] =
        { 'crr', vim.lsp.buf.code_action, desc = 'Code Action', mode = { 'n', 'v' }, has = 'codeAction' }
      keys[#keys + 1] = { 'crn', "<cmd>lua require('live-rename').rename()<cr>", desc = 'Rename', has = 'rename' }
      keys[#keys + 1] = { '<leader>cr', "<cmd>lua require('live-rename').rename()<cr>" }
    end,
  },
}
