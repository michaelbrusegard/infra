-- Prevent automatic comments on new lines
vim.api.nvim_create_autocmd('BufEnter', {
  group = vim.api.nvim_create_augroup('no_auto_comment', { clear = true }),
  command = 'set fo-=c fo-=r fo-=o',
})

-- Auto save on buffer leave or focus lost
vim.api.nvim_create_autocmd({ 'BufLeave', 'FocusLost' }, {
  group = vim.api.nvim_create_augroup('auto_save', { clear = true }),
  command = [[if &modified && !&readonly && expand("%") != "" && &buftype == "" | silent! update | endif]],
})
