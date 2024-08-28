local M = {}

local skip_foldexpr = {}
local skip_check = assert(vim.uv.new_check())

-- Function to create folds
function M.foldexpr()
  local buf = vim.api.nvim_get_current_buf()
  if skip_foldexpr[buf] then
    return '0'
  end
  if vim.bo[buf].buftype ~= '' then
    return '0'
  end
  if vim.bo[buf].filetype == '' then
    return '0'
  end
  local ok = pcall(vim.treesitter.get_parser, buf)
  if ok then
    return vim.treesitter.foldexpr()
  end
  skip_foldexpr[buf] = true
  skip_check:start(function()
    skip_foldexpr = {}
    skip_check:stop()
  end)
  return '0'
end

local function get_signs(buf, lnum)
  local signs = {}
  local extmarks = vim.api.nvim_buf_get_extmarks(
    buf,
    -1,
    { lnum - 1, 0 },
    { lnum - 1, -1 },
    { details = true, type = 'sign' }
  )
  for _, extmark in pairs(extmarks) do
    signs[#signs + 1] = {
      name = extmark[4].sign_hl_group or extmark[4].sign_name or '',
      text = extmark[4].sign_text,
      texthl = extmark[4].sign_hl_group,
      priority = extmark[4].priority,
    }
  end
  table.sort(signs, function(a, b)
    return (a.priority or 0) < (b.priority or 0)
  end)
  return signs
end

local function get_mark(buf, lnum)
  local marks = vim.fn.getmarklist(buf)
  vim.list_extend(marks, vim.fn.getmarklist())
  for _, mark in ipairs(marks) do
    if mark.pos[1] == buf and mark.pos[2] == lnum and mark.mark:match('[a-zA-Z]') then
      return { text = mark.mark:sub(2), texthl = 'DiagnosticHint' }
    end
  end
end

local function icon(sign, len)
  sign = sign or {}
  len = len or 2
  local text = vim.fn.strcharpart(sign.text or '', 0, len)
  text = text .. string.rep(' ', len - vim.fn.strchars(text))
  return sign.texthl and ('%#' .. sign.texthl .. '#' .. text .. '%*') or text
end

function M.statuscolumn()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  local is_file = vim.bo[buf].buftype == ''
  local components = { '', '', '' }
  local signs = get_signs(buf, vim.v.lnum)
  local left, right, fold, githl
  for _, s in ipairs(signs) do
    if s.name and s.name:find('GitSign') then
      right = s
      githl = s['texthl']
    else
      left = s
    end
  end
  vim.api.nvim_win_call(win, function()
    if vim.fn.foldclosed(vim.v.lnum) >= 0 then
      fold = { text = vim.opt.fillchars:get().foldclose or '', texthl = githl or 'Folded' }
    end
  end)
  if vim.g.show_marks then
    components[1] = icon(get_mark(buf, vim.v.lnum) or left)
  end
  components[3] = is_file and icon(fold or right) or ''
  if vim.v.virtnum == 0 then
    components[2] = '%l'
    components[2] = '%=' .. components[2] .. ' '
  end
  if vim.v.virtnum ~= 0 then
    components[2] = '%= '
  end
  return table.concat(components, '')
end

return M
