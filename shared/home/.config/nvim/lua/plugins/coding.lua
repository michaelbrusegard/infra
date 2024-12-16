return {
  { 'echasnovski/mini.pairs', enabled = false },
  { import = 'lazyvim.plugins.extras.coding.yanky' },
  {
    'gbprod/substitute.nvim',
    event = 'LazyFile',
    opts = {
      highlight_substituted_text = {
        timer = 150,
      },
    },
    keys = {
      { 'p', "<cmd>lua require('substitute').operator()<cr>", desc = 'Paste Text' },
      { 'pp', "<cmd>lua require('substitute').line()<cr>", desc = 'Paste Line' },
      { 'P', "<cmd>lua require('substitute').eol()<cr>", desc = 'Paste EOL' },
      { 'p', "<cmd>lua require('substitute').visual()<cr>", mode = { 'x' }, desc = 'Paste Visual' },
    },
  },
  {
    'saghen/blink.cmp',
    opts = { keymap = { preset = 'default' } },
  },
}
