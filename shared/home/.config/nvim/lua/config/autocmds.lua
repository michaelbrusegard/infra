-- Check if file was changed outside of Neovim
vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
  group = vim.api.nvim_create_augroup('checktime', { clear = true }),
  callback = function()
    if vim.o.buftype ~= 'nofile' then
      vim.cmd('checktime')
    end
  end,
})

-- Highlight when yanking text
vim.cmd('highlight HighlightYank guifg=#f9e2af guibg=#3f3b41')
vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('highlight_yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank({ higroup = 'HighlightYank', timeout = 200 })
  end,
})

-- Disable line numbers when in terminal mode and start in insert mode
vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('terminal', { clear = true }),
  callback = function()
    vim.opt.number = false
    vim.opt.relativenumber = false
    vim.cmd('startinsert')
  end,
})

-- Prevent automatic comments on new lines
vim.api.nvim_create_autocmd('BufEnter', {
  group = vim.api.nvim_create_augroup('no_auto_comment', { clear = true }),
  command = 'set fo-=c fo-=r fo-=o',
})

-- Remove trailing whitespace on save
vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('remove_trailing_whitespace', { clear = true }),
  command = ':%s/\\s\\+$//e',
})

-- Auto save on buffer leave or focus lost
vim.api.nvim_create_autocmd({ 'BufLeave', 'FocusLost' }, {
  group = vim.api.nvim_create_augroup('auto_save', { clear = true }),
  command = [[if &modified && !&readonly && expand("%") != "" && &buftype == "" | silent! update | endif]],
})

-- Resize splits when resizing window
vim.api.nvim_create_autocmd('VimResized', {
  group = vim.api.nvim_create_augroup('resize_splits', { clear = true }),
  command = 'wincmd =',
})

-- Make sure open float is false when leaving a foating window
local float_filetypes = { 'lazy', 'mason', 'git', 'fzf', 'harpoon', 'lspinfo', 'noice' }

vim.api.nvim_create_autocmd('BufLeave', {
  group = vim.api.nvim_create_augroup('float_open', { clear = true }),
  callback = function()
    if vim.tbl_contains(float_filetypes, vim.bo.filetype) then
      vim.g.float_open = false
    end
  end,
})

-- Go to last loc when opening a buffer
vim.api.nvim_create_autocmd('BufReadPost', {
  group = vim.api.nvim_create_augroup('last_loc', { clear = true }),
  callback = function(event)
    local exclude = { 'gitcommit' }
    local buf = event.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].lazyvim_last_loc then
      return
    end
    vim.b[buf].lazyvim_last_loc = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Close some filetypes with <q>
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('close_with_q', { clear = true }),
  pattern = {
    'help',
    'lspinfo',
    'grug-far',
    'qf',
    'tsplayground',
    'neotest-output',
    'checkhealth',
    'neotest-summary',
    'neotest-output-panel',
    'dbout',
    'gitsigns.blame',
    'molten_output',
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<cr>', {
      buffer = event.buf,
      silent = true,
      desc = 'Quit buffer',
    })
  end,
})

-- Close filetypes with <esc>
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('close_with_esc', { clear = true }),
  pattern = {
    'lazy',
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set('n', '<esc>', '<cmd>close<cr>', {
      buffer = event.buf,
      silent = true,
      desc = 'Quit buffer',
    })
  end,
})

-- Make it easier to close man-files when opened inline
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('man_unlisted', { clear = true }),
  pattern = { 'man' },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
  end,
})

-- Wrap and check for spell in text filetypes
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('wrap_spell', { clear = true }),
  pattern = { 'text', 'plaintex', 'typst', 'gitcommit', 'markdown' },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

-- Fix conceallevel for json files
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('json_conceal', { clear = true }),
  pattern = { 'json', 'jsonc', 'json5' },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

-- Auto create dir when saving a file, in case some intermediate directory does not exist
vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('auto_create_dir', { clear = true }),
  callback = function(event)
    if event.match:match('^%w%w+:[\\/][\\/]') then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ':p:h'), 'p')
  end,
})

-- Open filetypes with corresponding applications
local file_types = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'avif',
  'pdf',
  'mp3',
  'mp4',
  'xls',
  'xlsx',
  'xopp',
  'doc',
  'docx',
}
local binfiles_group = vim.api.nvim_create_augroup('binFiles', { clear = true })

for _, ext in ipairs(file_types) do
  vim.api.nvim_create_autocmd('BufReadCmd', {
    pattern = '*.' .. ext,
    group = binfiles_group,
    callback = require('util.autocmds').open_app,
  })
end

-- Setup filetypes
vim.filetype.add({
  extension = {
    ['http'] = 'http',
    ['vert'] = 'glsl',
    ['frag'] = 'glsl',
    ['comp'] = 'glsl',
    ['rchit'] = 'glsl',
    ['rmiss'] = 'glsl',
    ['rahit'] = 'glsl',
  },
})
