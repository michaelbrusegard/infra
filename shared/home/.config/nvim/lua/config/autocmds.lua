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

-- Open filetypes with system applications
-- local file_types = {
--   'png',
--   'jpg',
--   'jpeg',
--   'gif',
--   'webp',
--   'avif',
--   'pdf',
--   'mp3',
--   'mp4',
--   'xls',
--   'xlsx',
--   'xopp',
--   'doc',
--   'docx',
-- }
-- local binfiles_group = vim.api.nvim_create_augroup('binFiles', { clear = true })
--
-- for _, ext in ipairs(file_types) do
--   vim.api.nvim_create_autocmd('BufReadCmd', {
--     pattern = '*.' .. ext,
--     group = binfiles_group,
--     callback = function()
--       local prev_buf = vim.fn.bufnr('%')
--       local fn = vim.fn.expand('%:p')
--       vim.fn.jobstart('open "' .. fn .. '"')
--       vim.api.nvim_echo({ { string.format('Opening file: %s', fn), 'None' } }, false, {})
--       if vim.fn.buflisted(prev_buf) == 1 then
--         vim.api.nvim_set_current_buf(prev_buf)
--       end
--       vim.api.nvim_buf_delete(0, { force = true })
--     end,
--   })
-- end
