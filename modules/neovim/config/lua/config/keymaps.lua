-- Split windows
vim.keymap.set({ 'n' }, '<C-\\>', '<cmd>split<cr>', { silent = true, desc = 'Split window horizontally' })
vim.keymap.set({ 'n' }, '<C-S-\\>', '<cmd>vsplit<cr>', { silent = true, desc = 'Split window vertically' })

-- Move between windows
vim.keymap.set('n', '<C-h>', '<C-w>h', { silent = true, desc = 'Move to left window' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { silent = true, desc = 'Move to bottom window' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { silent = true, desc = 'Move to top window' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { silent = true, desc = 'Move to right window' })

-- Swap windows
vim.keymap.set('n', '<C-S-h>', '<C-w>H', { silent = true, desc = 'Swap window left' })
vim.keymap.set('n', '<C-S-j>', '<C-w>J', { silent = true, desc = 'Swap window down' })
vim.keymap.set('n', '<C-S-k>', '<C-w>K', { silent = true, desc = 'Swap window up' })
vim.keymap.set('n', '<C-S-l>', '<C-w>L', { silent = true, desc = 'Swap window right' })

-- Resize windows
vim.keymap.set('n', '<C-u>', '<cmd>resize -2<CR>', { silent = true, desc = 'Decrease window height' })
vim.keymap.set('n', '<C-i>', '<cmd>resize +2<CR>', { silent = true, desc = 'Increase window height' })
vim.keymap.set('n', '<C-o>', '<cmd>vertical resize -2<CR>', { silent = true, desc = 'Decrease window width' })
vim.keymap.set('n', '<C-p>', '<cmd>vertical resize +2<CR>', { silent = true, desc = 'Increase window width' })

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
