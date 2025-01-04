return {
  { 'folke/tokyonight.nvim', enabled = false },
  { 'catppuccin/nvim', enabled = false },
  {
    'rose-pine/neovim',
    name = 'rose-pine',
    opts = {
      dark_variant = 'moon',
    },
    config = function()
      vim.cmd('colorscheme rose-pine-moon')
    end,
  },
}
