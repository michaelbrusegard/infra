-- Load options here, before lazy init while sourcing plugin modules
-- This is needed to make sure options will be correctly applied
-- after installing missing plugins
require('config.options')

-- Defer built-in clipboard handling: "xsel" and "pbcopy" can be slow
local lazy_clipboard = vim.opt.clipboard
vim.opt.clipboard = ''

-- Autocmds can be loaded lazily when not opening a file
local lazy_autocmds = vim.fn.argc(-1) == 0
if not lazy_autocmds then
  require('config.autocmds')
end

vim.api.nvim_create_autocmd('User', {
  group = vim.api.nvim_create_augroup('Lazyload', { clear = true }),
  pattern = 'VeryLazy',
  callback = function()
    if lazy_autocmds then
      require('config.autocmds')
    end
    require('config.keymaps')
    vim.opt.clipboard = lazy_clipboard
    require('util.root').setup()
  end,
})

-- Bootstrap plugin managers
local path = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(path) then
  local repo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', repo, path }
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { out, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(path)

-- This autocmd will only trigger when a file was loaded from the cmdline.
-- It will render the file as quickly as possible.
vim.api.nvim_create_autocmd('BufReadPost', {
  once = true,
  callback = function(event)
    -- Skip if we already entered vim
    if vim.v.vim_did_enter == 1 then
      return
    end

    -- Try to guess the filetype (may change later on during Neovim startup)
    local ft = vim.filetype.match { buf = event.buf }
    if ft then
      -- Add treesitter highlights and fallback to syntax
      local lang = vim.treesitter.language.get_lang(ft)
      if not (lang and pcall(vim.treesitter.start, event.buf, lang)) then
        vim.bo[event.buf].syntax = ft
      end

      -- Trigger early redraw
      vim.cmd([[redraw]])
    end
  end,
})

-- Add support for the LazyFile event
local Event = require('lazy.core.handler.event')

Event.mappings.LazyFile = { id = 'LazyFile', event = { 'BufReadPost', 'BufNewFile', 'BufWritePre' } }
Event.mappings['User LazyFile'] = Event.mappings.LazyFile

-- Setup lazy.nvim
require('lazy').setup {
  spec = {
    { import = 'plugins' },
  },
  install = { colorscheme = { 'catppuccin-mocha' } },
  checker = { enabled = true },
  ui = {
    size = { width = 0.85, height = 0.85 },
    border = 'rounded',
    wrap = false,
    backdrop = 100,
    icons = {
      lazy = '',
    },
  },
  performance = {
    rtp = {
      disabled_plugins = {
        'gzip',
        'netrwPlugin',
        'tarPlugin',
        'tohtml',
        'tutor',
        'zipPlugin',
      },
    },
  },
}
