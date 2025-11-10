-- Spellcheck
vim.opt.spelllang = 'en,nb'

-- Reload files changed outside of Neovim
vim.opt.autoread = true

-- Disable order check
vim.g.lazyvim_check_order = false

-- Set snacks as the picker
vim.g.lazyvim_picker = 'snacks'

-- Require config for prettier
vim.g.lazyvim_prettier_needs_config = true

-- Set zathura as the default latex viewer
vim.g.vimtex_view_method = 'zathura'

-- Use basedpyright
vim.g.lazyvim_python_lsp = 'basedpyright'

-- Filetypes
vim.filetype.add({
  extension = {
    gs = 'javascript',
  },
})
