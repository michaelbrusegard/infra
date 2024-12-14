return {
  { 'folke/lazy.nvim', version = false },
  {
    'LazyVim/LazyVim',
    version = false,
    opts = {
      colorscheme = 'catppuccin',
    },
  },
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
  { 'folke/tokyonight.nvim', enabled = false },
  { 'folke/flash.nvim', enabled = false },
  { 'folke/trouble.nvim', enabled = false },
  { 'nvim-neo-tree/neo-tree.nvim', enabled = false },
  { 'akinsho/bufferline.nvim', enabled = false },
}
