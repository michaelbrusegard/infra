local M = {}

-- Function to escape special characters for search
function M.escape_term(term)
  return vim.fn.escape(term, '/\\')
end

-- Function to delete marks on the current line
function M.delmarks()
  local current_line = vim.fn.line('.')
  local marks_to_check = {}
  for mark = 97, 122 do -- ASCII values for 'a' to 'z'
    table.insert(marks_to_check, string.char(mark))
  end
  for mark = 65, 90 do -- ASCII values for 'A' to 'Z'
    table.insert(marks_to_check, string.char(mark))
  end
  for _, mark in ipairs(marks_to_check) do
    local mark_line = vim.fn.getpos("'" .. mark)[2]
    if mark_line == current_line then
      vim.cmd('delmarks ' .. mark)
    end
  end
end

-- Open Lazy
function M.open_lazy()
  if not vim.g.float_open then
    vim.g.float_open = true
    vim.cmd('Lazy')
  end
end

-- Open Mason
function M.open_mason()
  if not vim.g.float_open then
    vim.g.float_open = true
    vim.cmd('Mason')
  end
end

-- Maximize window
local is_maximized = false
local previous_options = {}

function M.maximize()
  if is_maximized then
    for _, opt in ipairs(previous_options) do
      vim.o[opt.k] = opt.v
    end
    previous_options = {}
    vim.cmd('wincmd =')
    is_maximized = false
  else
    local function save(k)
      table.insert(previous_options, 1, { k = k, v = vim.o[k] })
    end
    save('winwidth')
    save('winheight')
    save('winminwidth')
    save('winminheight')
    vim.o.winwidth = 999
    vim.o.winheight = 999
    vim.o.winminwidth = 10
    vim.o.winminheight = 4
    vim.cmd('wincmd =')
    vim.api.nvim_create_autocmd('ExitPre', {
      once = true,
      group = vim.api.nvim_create_augroup('toggle_maximize', { clear = true }),
      desc = 'Restore width/height when close Neovim while maximized',
      callback = function()
        M.maximize()
      end,
    })
    is_maximized = true
  end
end

return M
