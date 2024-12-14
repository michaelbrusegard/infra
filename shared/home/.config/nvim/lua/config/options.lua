-- Spellcheck
vim.opt.spelllang = 'en,nb'

-- Setup python
local venv = vim.fn.expand('~/.pyenv/versions/neovim')
vim.g.python3_host_prog = venv .. '/bin/python'
vim.env.PATH = venv .. '/bin:' .. vim.env.PATH
vim.env.PYENV_VERSION = vim.fn.system('pyenv version'):match('(%S+)%s+%(.-%)')
