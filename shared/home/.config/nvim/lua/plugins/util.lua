return {
  { import = 'lazyvim.plugins.extras.util.dot' },
  { import = 'lazyvim.plugins.extras.util.mini-hipatterns' },
  { import = 'lazyvim.plugins.extras.util.rest' },
  {
    'folke/snacks.nvim',
    opts = {
      indent = {
        indent = {
          char = '▏',
        },
        scope = {
          underline = true,
          char = '▏',
        },
      },
    },
  },
}
