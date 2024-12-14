return {
  { 'folke/lazy.nvim', version = false },
  {
    'LazyVim/LazyVim',
    branch = 'v14',
    version = false,
    opts = {
      colorscheme = 'catppuccin',
    },
  },
  {
    'folke/snacks.nvim',
    opts = {
      indent = {
        scope = {
          char = '▏',
          underline = true,
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
