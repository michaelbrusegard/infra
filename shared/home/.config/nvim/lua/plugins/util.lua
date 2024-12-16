return {
  { import = 'lazyvim.plugins.extras.util.dot' },
  { import = 'lazyvim.plugins.extras.util.mini-hipatterns' },
  { import = 'lazyvim.plugins.extras.util.rest' },
  {
    'folke/snacks.nvim',
    -- Use latest when underline bug is fixed
    version = '2.9.0',
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
