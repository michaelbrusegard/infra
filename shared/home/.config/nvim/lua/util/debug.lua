local M = {}

function M.get_args(config)
  local args = type(config.args) == 'function' and (config.args() or {}) or config.args or {}
  config = vim.deepcopy(config)
  config.args = function()
    local new_args = vim.fn.input('Run with args: ', table.concat(args, ' '))
    return vim.split(vim.fn.expand(new_args), ' ')
  end
  return config
end

return M
