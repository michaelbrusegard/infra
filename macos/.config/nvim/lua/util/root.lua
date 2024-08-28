local M = {}

M.spec = { 'lsp', { '.git', 'lua' }, 'cwd' }

M.detectors = {}

function M.detectors.cwd()
  return { vim.uv.cwd() }
end

function M.detectors.pattern(buf, patterns)
  patterns = type(patterns) == 'string' and { patterns } or patterns
  local path = M.bufpath(buf) or vim.uv.cwd()
  local pattern = vim.fs.find(function(name)
    for _, p in ipairs(patterns) do
      if name == p then
        return true
      end
      if p:sub(1, 1) == '*' and name:find(vim.pesc(p:sub(2)) .. '$') then
        return true
      end
    end
    return false
  end, { path = path, upward = true })[1]
  return pattern and { vim.fs.dirname(pattern) } or {}
end

function M.bufpath(buf)
  return M.realpath(vim.api.nvim_buf_get_name(assert(buf)))
end

function M.realpath(path)
  if path == '' or path == nil then
    return nil
  end
  path = vim.uv.fs_realpath(path) or path
  return require('lazy.core.util').norm(path)
end

function M.resolve(spec)
  if M.detectors[spec] then
    return M.detectors[spec]
  elseif type(spec) == 'function' then
    return spec
  end
  return function(buf)
    return M.detectors.pattern(buf, spec)
  end
end

function M.detect(opts)
  opts = opts or {}
  opts.spec = opts.spec or type(vim.g.root_spec) == 'table' and vim.g.root_spec or M.spec
  opts.buf = (opts.buf == nil or opts.buf == 0) and vim.api.nvim_get_current_buf() or opts.buf

  local ret = {}
  for _, spec in ipairs(opts.spec) do
    local paths = M.resolve(spec)(opts.buf)
    paths = paths or {}
    paths = type(paths) == 'table' and paths or { paths }
    local roots = {}
    for _, p in ipairs(paths) do
      local pp = M.realpath(p)
      if pp and not vim.tbl_contains(roots, pp) then
        roots[#roots + 1] = pp
      end
    end
    table.sort(roots, function(a, b)
      return #a > #b
    end)
    if #roots > 0 then
      ret[#ret + 1] = { spec = spec, paths = roots }
      if opts.all == false then
        break
      end
    end
  end
  return ret
end

function M.info()
  local spec = type(vim.g.root_spec) == 'table' and vim.g.root_spec or M.spec

  local roots = M.detect({ all = true })
  local lines = {}
  local first = true
  for _, root in ipairs(roots) do
    for _, path in ipairs(root.paths) do
      lines[#lines + 1] = ('- [%s] `%s` **(%s)**'):format(
        first and 'x' or ' ',
        path,
        type(root.spec) == 'table' and table.concat(root.spec, ', ') or root.spec
      )
      first = false
    end
  end
  lines[#lines + 1] = '```lua'
  lines[#lines + 1] = 'vim.g.root_spec = ' .. vim.inspect(spec)
  lines[#lines + 1] = '```'
  require('lazy.core.util').info(lines, { title = 'Roots' })
  return roots[1] and roots[1].paths[1] or vim.uv.cwd()
end

M.cache = {}

function M.setup()
  vim.api.nvim_create_user_command('LazyRoot', function()
    M.info()
  end, { desc = 'Roots for the current buffer' })

  vim.api.nvim_create_autocmd({ 'LspAttach', 'BufWritePost', 'DirChanged', 'BufEnter' }, {
    group = vim.api.nvim_create_augroup('root_cache', { clear = true }),
    callback = function(event)
      M.cache[event.buf] = nil
    end,
  })
end

-- returns the root directory based on:
-- * lsp workspace folders
-- * lsp root_dir
-- * root pattern of filename of the current buffer
-- * root pattern of cwd
function M.get(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local ret = M.cache[buf]
  if not ret then
    local roots = M.detect({ all = false, buf = buf })
    ret = roots[1] and roots[1].paths[1] or vim.uv.cwd()
    M.cache[buf] = ret
  end
  return ret
end

function M.git()
  local root = M.get()
  local git_root = vim.fs.find('.git', { path = root, upward = true })[1]
  local ret = git_root and vim.fn.fnamemodify(git_root, ':h') or root
  return ret
end

return M
