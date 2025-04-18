-- Split windows
vim.keymap.set({ 'x', 'n' }, '<C-/>', '<cmd>vsplit<cr>', { silent = true, desc = 'Split window vertically' })
vim.keymap.set({ 'x', 's' }, '<C-S-/>', '<cmd>split<cr>', { silent = true, desc = 'Split window horizontally' })

-- Move between windows
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-h>', '<C-w>h', { silent = true, desc = 'Move to left window' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-j>', '<C-w>j', { silent = true, desc = 'Move to bottom window' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-k>', '<C-w>k', { silent = true, desc = 'Move to top window' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-l>', '<C-w>l', { silent = true, desc = 'Move to right window' })

-- Swap windows
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-S-h>', '<C-w>H', { silent = true, desc = 'Swap window left' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-S-j>', '<C-w>J', { silent = true, desc = 'Swap window down' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-S-k>', '<C-w>K', { silent = true, desc = 'Swap window up' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-S-l>', '<C-w>L', { silent = true, desc = 'Swap window right' })

-- File explorer
vim.keymap.set('n', '-', function()
  Snacks.explorer({ cwd = LazyVim.root() })
end, { desc = 'Explorer Snacks (current dir)' })

-- Marks
vim.keymap.set('n', 'dm', function()
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
end, { desc = 'Delete Marks', silent = true })
