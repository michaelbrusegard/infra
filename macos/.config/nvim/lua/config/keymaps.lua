-- Copy to system clipboard with super + c
vim.keymap.set({ 'n', 'x' }, '<char-0xca>', '"+y', { silent = true })

-- Paste from system clipboard with super + v
vim.keymap.set({ 'n', 'x' }, '<char-0xcb>', '"+p', { silent = true })
vim.keymap.set('i', '<char-0xcb>', function()
  return vim.api.nvim_replace_termcodes('<esc>"+pi', true, true, true)
end, { expr = true, silent = true })
vim.keymap.set('c', '<char-0xcb>', '<c-R>+', { silent = true })

-- Cut to system clipboard with super + x
vim.keymap.set({ 'n', 'x' }, '<char-0xcc>', '"+x', { silent = true })

-- Save file with super + s
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xcd>', '<cmd>w<cr><esc>', { silent = true })

-- Quit with super + w
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xda>', '<cmd>q<cr>', { silent = true })

-- Quit All with shift + super + w
vim.keymap.set('n', '<char-0xdb>', '<cmd>qa<cr>', { silent = true })

-- Split windows with super + - and super + =
vim.keymap.set('n', '<char-0xdc>', '<c-w>s', { silent = true })
vim.keymap.set('n', '<char-0xdd>', '<c-w>v', { silent = true })

-- Move to window using the super + hjkl keys
vim.keymap.set('n', '<char-0xe0>', "<cmd>lua require('smart-splits').move_cursor_left()<cr>", { silent = true })
vim.keymap.set('n', '<char-0xe1>', "<cmd>lua require('smart-splits').move_cursor_down()<cr>", { silent = true })
vim.keymap.set('n', '<char-0xe2>', "<cmd>lua require('smart-splits').move_cursor_up()<cr>", { silent = true })
vim.keymap.set('n', '<char-0xe3>', "<cmd>lua require('smart-splits').move_cursor_right()<cr>", { silent = true })

-- Resize window using ctrl + super + hjkl keys
vim.keymap.set('n', '<Char-0xe4>', "<cmd>lua require('smart-splits').resize_left()<cr>", { silent = true })
vim.keymap.set('n', '<Char-0xe5>', "<cmd>lua require('smart-splits').resize_down()<cr>", { silent = true })
vim.keymap.set('n', '<Char-0xe6>', "<cmd>lua require('smart-splits').resize_up()<cr>", { silent = true })
vim.keymap.set('n', '<Char-0xe7>', "<cmd>lua require('smart-splits').resize_right()<cr>", { silent = true })

-- Fix up/down for wrapped lines
vim.keymap.set({ 'n', 'x' }, 'j', "v:count == 0 ? 'gj' : 'j'", { desc = 'Down', expr = true, silent = true })
vim.keymap.set({ 'n', 'x' }, '<down>', "v:count == 0 ? 'gj' : 'j'", { desc = 'Down', expr = true, silent = true })
vim.keymap.set({ 'n', 'x' }, 'k', "v:count == 0 ? 'gk' : 'k'", { desc = 'Up', expr = true, silent = true })
vim.keymap.set({ 'n', 'x' }, '<up>', "v:count == 0 ? 'gk' : 'k'", { desc = 'Up', expr = true, silent = true })

-- Delete character under cursor without overriding clipboard
vim.keymap.set('n', 'x', '"_x', { silent = true })

-- Exit terminal mode in the builtin terminal with a shortcut that is easier
vim.keymap.set('t', '<esc><esc>', '<c-\\><c-n>', { desc = 'Exit terminal mode', silent = true })

-- Keep selection when indenting
vim.keymap.set('x', '>', '>gv', { silent = true })
vim.keymap.set('x', '<', '<gv', { silent = true })

-- Map / to search for selected text in visual mode
vim.keymap.set('x', '/', 'y/\\V<c-r>=v:lua.require("util.keymaps").escape_term(@")<cr><cr>', { silent = true })

-- Map ? to search backward for selected text in visual mode
vim.keymap.set('x', '?', 'y?\\V<c-r>=v:lua.require("util.keymaps").escape_term(@")<cr><cr>', { silent = true })

-- Properly position cursor when searching and open closed folds
vim.keymap.set('n', 'n', "'Nn'[v:searchforward].'zv'", { expr = true, desc = 'Next Search Result', silent = true })
vim.keymap.set('x', 'n', "'Nn'[v:searchforward]", { expr = true, desc = 'Next Search Result', silent = true })
vim.keymap.set('o', 'n', "'Nn'[v:searchforward]", { expr = true, desc = 'Next Search Result', silent = true })
vim.keymap.set('n', 'N', "'nN'[v:searchforward].'zv'", { expr = true, desc = 'Prev Search Result', silent = true })
vim.keymap.set('x', 'N', "'nN'[v:searchforward]", { expr = true, desc = 'Prev Search Result', silent = true })
vim.keymap.set('o', 'N', "'nN'[v:searchforward]", { expr = true, desc = 'Prev Search Result', silent = true })

-- Start new undo block when entering any of these characters
vim.keymap.set('i', ',', ',<c-g>u', { silent = true })
vim.keymap.set('i', '.', '.<c-g>u', { silent = true })
vim.keymap.set('i', ';', ';<c-g>u', { silent = true })

-- Buffers
vim.keymap.set('n', ']b', '<cmd>bnext<cr>', { desc = 'Next Buffer', silent = true })
vim.keymap.set('n', '[b', '<cmd>bprevious<cr>', { desc = 'Prev Buffer', silent = true })
vim.keymap.set('n', '<leader>bb', '<cmd>e #<cr>', { desc = 'Switch to Other Buffer', silent = true })
vim.keymap.set('n', '<leader>bd', require('util.keymaps').bufremove, { desc = 'Delete Buffer', silent = true })
vim.keymap.set('n', '<leader>bD', '<cmd>bd<cr>', { desc = 'Delete Buffer and Window', silent = true })

-- New file
vim.keymap.set('n', '<leader>fn', '<cmd>enew<cr>', { desc = 'New File', silent = true })

-- Quickfix
vim.keymap.set('n', '[q', vim.cmd.cprev, { desc = 'Prev Quickfix', silent = true })
vim.keymap.set('n', ']q', vim.cmd.cnext, { desc = 'Next Quickfix', silent = true })

-- Diagnostics
vim.keymap.set('n', '<leader>cd', vim.diagnostic.open_float, { desc = 'Line Diagnostics', silent = true })
vim.keymap.set(
  'n',
  ']d',
  '<cmd>lua vim.diagnostic.jump({ count = 1, float = true })<cr>',
  { desc = 'Next Diagnostic', silent = true }
)
vim.keymap.set(
  'n',
  '[d',
  '<cmd>lua vim.diagnostic.jump({ count = -1, float = true })<cr>',
  { desc = 'Prev Diagnostic', silent = true }
)

-- Marks
vim.keymap.set('n', 'dm', require('util.keymaps').delmarks, { desc = 'Delete Marks', silent = true })

-- Disable tab keymaps
vim.keymap.set('n', 'gt', '<nop>', { desc = '', noremap = true, silent = true })
vim.keymap.set('n', 'gT', '<nop>', { desc = '', noremap = true, silent = true })

-- Windows
vim.keymap.set('n', '<leader>w', '<c-w>', { desc = 'Windows', remap = true, silent = true })
vim.keymap.set('n', '<c-w>-', '<c-w>s', { desc = 'Split Window Below', remap = true, silent = true })
vim.keymap.set('n', '<c-w>=', '<c-w>v', { desc = 'Split Window Right', remap = true, silent = true })
vim.keymap.set('n', '<c-w>d', '<c-w>c', { desc = 'Delete Window', remap = true, silent = true })
vim.keymap.set('n', '<leader>wm', require('util.keymaps').maximize, { desc = 'Maximise Window', silent = true })

-- Git
vim.keymap.set('n', '<leader>gg', require('util.keymaps').open_git, { desc = 'Git Menu', silent = true })
vim.keymap.set(
  'n',
  '<leader>gC',
  require('util.keymaps').open_git_file_commits,
  { desc = 'Git Commits Log', silent = true }
)
vim.keymap.set('n', '<leader>gB', require('util.keymaps').open_git_blame, { desc = 'Git Blame Log', silent = true })

-- Signs
vim.keymap.set('n', '<leader>ls', require('util.keymaps').toggle_signs, { desc = 'Signcolumn', silent = true })

-- Open Mason
vim.keymap.set('n', '<leader>lm', require('util.keymaps').open_mason, { desc = 'Mason', silent = true })

-- Open Lazy
vim.keymap.set('n', '<leader>ll', require('util.keymaps').open_lazy, { desc = 'Lazy', silent = true })
