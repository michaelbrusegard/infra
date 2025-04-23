return {
  { import = 'lazyvim.plugins.extras.coding.yanky' },
  {
    'saghen/blink.cmp',
    lazy = true,
    dependencies = { 'saghen/blink.compat' },
    opts = {
      keymap = { preset = 'default' }
      sources = {
        default = { 'avante_commands', 'avante_mentions', 'avante_files' },
        compat = {
          'avante_commands',
          'avante_mentions',
          'avante_files',
        },
        providers = {
          avante_commands = {
            name = 'avante_commands',
            module = 'blink.compat.source',
            score_offset = 90,
            opts = {},
          },
          avante_files = {
            name = 'avante_files',
            module = 'blink.compat.source',
            score_offset = 100,
            opts = {},
          },
          avante_mentions = {
            name = 'avante_mentions',
            module = 'blink.compat.source',
            score_offset = 1000,
            opts = {},
          },
        },
      },
    },
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
