-- Copy to system clipboard with super + c
vim.keymap.set({ 'n', 'x' }, '<char-0xca>', '"+y', { silent = true })

-- Paste from system clipboard with super + v
vim.keymap.set({ 'n', 'x' }, '<char-0xcb>', '"+p', { silent = true })
vim.keymap.set('i', '<char-0xcb>', function()
  return vim.api.nvim_replace_termcodes('<esc>"+pi', true, true, true)
end, { expr = true, silent = true })
vim.keymap.set('c', '<char-0xcb>', '<c-R>+', { silent = true })

-- Cut to system clipboard with super + x
vim.keymap.set({ 'x', 'n' }, '<char-0xcc>', '"+x', { silent = true })

-- Save file with super + s
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xcd>', '<cmd>w<cr><esc>', { silent = true })

-- Quit with super + w
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xda>', '<cmd>q<cr>', { silent = true })

-- Quit All with shift + super + w
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xdb>', '<cmd>qa<cr>', { silent = true })

-- Split windows with super + - and super + =
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xdc>', '<cmd>split<cr>', { silent = true })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<char-0xdd>', '<cmd>vsplit<cr>', { silent = true })

-- Move to window using the super + hjkl keys
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<char-0xe0>',
  "<cmd>lua require('smart-splits').move_cursor_left()<cr>",
  { silent = true }
)
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<char-0xe1>',
  "<cmd>lua require('smart-splits').move_cursor_down()<cr>",
  { silent = true }
)
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<char-0xe2>',
  "<cmd>lua require('smart-splits').move_cursor_up()<cr>",
  { silent = true }
)
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<char-0xe3>',
  "<cmd>lua require('smart-splits').move_cursor_right()<cr>",
  { silent = true }
)

-- Resize window using ctrl + super + hjkl keys
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<Char-0xe4>',
  "<cmd>lua require('smart-splits').resize_left()<cr>",
  { silent = true }
)
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<Char-0xe5>',
  "<cmd>lua require('smart-splits').resize_down()<cr>",
  { silent = true }
)
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<Char-0xe6>',
  "<cmd>lua require('smart-splits').resize_up()<cr>",
  { silent = true }
)
vim.keymap.set(
  { 'i', 'x', 'n', 's' },
  '<Char-0xe7>',
  "<cmd>lua require('smart-splits').resize_right()<cr>",
  { silent = true }
)

vim.keymap.set('n', '<leader>gd', function()
  Snacks.terminal('lazydocker', { esc_esc = false, ctrl_hjkl = false })
end, { desc = 'Lazydocker' })
