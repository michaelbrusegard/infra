return {
  { import = 'lazyvim.plugins.extras.coding.yanky' },
  { import = 'lazyvim.plugins.extras.coding.mini-surround' },
  {
    'piersolenski/import.nvim',
    dependencies = {
      'folke/snacks.nvim',
    },
    opts = {
      picker = 'snacks',
    },
    keys = {
      {
        '<leader>i',
        function()
          require('import').pick()
        end,
        desc = 'Import',
      },
    },
  },
}
