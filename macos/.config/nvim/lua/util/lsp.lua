local M = {}

function M.on_attach(on_attach, name)
  return vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
      local buffer = args.buf
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and (not name or client.name == name) then
        return on_attach(client, buffer)
      end
    end,
  })
end

function M.extend_or_override(config, custom, ...)
  if type(custom) == 'function' then
    config = custom(config, ...) or config
  elseif custom then
    config = vim.tbl_deep_extend('force', config, custom)
  end
  return config
end

function M.action(action)
  return function()
    vim.lsp.buf.code_action({
      apply = true,
      context = {
        only = { action },
        diagnostics = {},
      },
    })
  end
end

function M.execute(opts)
  local params = {
    command = opts.command,
    arguments = opts.arguments,
  }
  if opts.open then
    require('trouble').open({
      mode = 'lsp_command',
      params = params,
    })
  else
    return vim.lsp.buf_request(0, 'workspace/executeCommand', params, opts.handler)
  end
end

return M
