-- Spellcheck
vim.opt.spelllang = 'en,nb'

-- Setup python
vim.g.lazyvim_python_lsp = 'basedpyright'
local venv = vim.fn.expand('~/.pyenv/versions/neovim')
vim.g.python3_host_prog = venv .. '/bin/python'
vim.env.PATH = venv .. '/bin:' .. vim.env.PATH
vim.env.PYENV_VERSION = vim.fn.system('pyenv version'):match('(%S+)%s+%(.-%)')

-- Set snacks as the picker
vim.g.lazyvim_picker = 'snacks'

-- Require config for prettier
vim.g.lazyvim_prettier_needs_config = true
