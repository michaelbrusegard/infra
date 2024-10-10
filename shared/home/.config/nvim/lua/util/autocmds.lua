local M = {}

function M.open_app()
  local prev_buf = vim.fn.bufnr('%')
  local fn = vim.fn.expand('%:p')
  vim.fn.jobstart('open "' .. fn .. '"')
  vim.api.nvim_echo({ { string.format('Opening file: %s', fn), 'None' } }, false, {})
  if vim.fn.buflisted(prev_buf) == 1 then
    vim.api.nvim_set_current_buf(prev_buf)
  end
  vim.api.nvim_buf_delete(0, { force = true })
end

return M
