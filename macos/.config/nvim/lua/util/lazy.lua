local M = {}

function M.is_loaded(name)
  local Config = require('lazy.core.config')
  return Config.plugins[name] and Config.plugins[name]._.loaded
end

function M.on_load(name, fn)
  if M.is_loaded(name) then
    fn(name)
  else
    vim.api.nvim_create_autocmd('User', {
      pattern = 'LazyLoad',
      callback = function(event)
        if event.data == name then
          fn(name)
          return true
        end
      end,
    })
  end
end

function M.get_plugin(name)
  return require('lazy.core.config').spec.plugins[name]
end

function M.opts(name)
  local plugin = M.get_plugin(name)
  if not plugin then
    return {}
  end
  local Plugin = require('lazy.core.plugin')
  return Plugin.values(plugin, 'opts', false)
end

function M.on_very_lazy(fn)
  vim.api.nvim_create_autocmd('User', {
    pattern = 'VeryLazy',
    callback = function()
      fn()
    end,
  })
end

function M.get_pkg_path(pkg, path, opts)
  pcall(require, 'mason')
  local root = vim.env.MASON or (vim.fn.stdpath('data') .. '/mason')
  opts = opts or {}
  opts.warn = opts.warn == nil and true or opts.warn
  path = path or ''
  local ret = root .. '/packages/' .. pkg .. '/' .. path
  if opts.warn and not vim.loop.fs_stat(ret) and not require('lazy.core.config').headless() then
    require('lazy.core.util').warn(
      ('Mason package path not found for **%s**:\n- `%s`\nYou may need to force update the package.'):format(pkg, path)
    )
  end
  return ret
end

return M
