local M = {}

function M.pick(command, opts)
  if vim.g.float_open then
    return
  end
  vim.g.float_open = true

  opts = opts or {}

  opts = vim.tbl_extend('force', {
    header = false,
  }, require('util.lazy').opts('ibhagwan/fzf-lua').command or {}, opts)

  if not opts.cwd and opts.root ~= false then
    opts.cwd = require('util.root').get { buf = opts.buf }
  end

  require('fzf-lua')[command](opts)
end

return M
