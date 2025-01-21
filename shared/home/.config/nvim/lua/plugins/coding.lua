return {
  { import = 'lazyvim.plugins.extras.coding.yanky' },
  {
    'saghen/blink.cmp',
    opts = { keymap = { preset = 'default' } },
  },
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
      { 'gp', 'p', desc = 'Paste After Cursor' },
      { 'gP', 'P', desc = 'Paste Before Cursor' },
      { 'po', ':put<CR>==', desc = 'Paste Line Below' },
      { 'pO', ':-1put<CR>==', desc = 'Paste Line Above' },
    },
  },
}
