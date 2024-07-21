local M = {}

-- Default keymaps to load initially
function M.default()
	-- Copy to system clipboard with super + c
	vim.keymap.set({ "n", "x" }, "<char-0xca>", '"+y')

	-- Paste from system clipboard with super + v
	vim.keymap.set({ "n", "x" }, "<char-0xcb>", '"+p')
	vim.keymap.set("i", "<char-0xcb>", function()
		return vim.api.nvim_replace_termcodes('<esc>"+pi', true, true, true)
	end, { expr = true })
	vim.keymap.set("c", "<char-0xcb>", "<c-R>+")

	-- Cut to system clipboard with super + x
	vim.keymap.set({ "n", "x" }, "<char-0xcc>", '"+x')

	-- Save file with super + s
	vim.keymap.set({ "i", "x", "n", "s" }, "<char-0xcd>", "<cmd>w<cr><esc>")

	-- Quit with super + w
	vim.keymap.set({ "i", "x", "n", "s" }, "<char-0xda>", "<cmd>q<cr>")

	-- Quit All with shift + super + w
	vim.keymap.set("n", "<char-0xdb>", "<cmd>qa<cr>")

	-- Split windows with super + - and super + =
	vim.keymap.set("n", "<char-0xdc>", "<c-w>s")
	vim.keymap.set("n", "<char-0xdd>", "<c-w>v")

	-- Move to window using the super + hjkl keys
	vim.keymap.set("n", "<char-0xe0>", "<cmd>lua require('plugins.smart-splits').move_cursor_left()<cr>")
	vim.keymap.set("n", "<char-0xe1>", "<cmd>lua require('plugins.smart-splits').move_cursor_down()<cr>")
	vim.keymap.set("n", "<char-0xe2>", "<cmd>lua require('plugins.smart-splits').move_cursor_up()<cr>")
	vim.keymap.set("n", "<char-0xe3>", "<cmd>lua require('plugins.smart-splits').move_cursor_right()<cr>")

	-- Resize window using ctrl + super + hjkl keys
	vim.keymap.set("n", "<Char-0xe4>", "<cmd>lua require('plugins.smart-splits').resize_left()<cr>")
	vim.keymap.set("n", "<Char-0xe5>", "<cmd>lua require('plugins.smart-splits').resize_down()<cr>")
	vim.keymap.set("n", "<Char-0xe6>", "<cmd>lua require('plugins.smart-splits').resize_up()<cr>")
	vim.keymap.set("n", "<Char-0xe7>", "<cmd>lua require('plugins.smart-splits').resize_right()<cr>")

	-- Fix up/down for wrapped lines
	vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
	vim.keymap.set({ "n", "x" }, "<down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
	vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
	vim.keymap.set({ "n", "x" }, "<up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

	-- Preserves clipboard when pasting with leader
	vim.keymap.set("x", "<leader>p", '"_dP', { desc = "Paste without overriding clipboard" })

	-- Preserve clipboard when deleting with leader
	vim.keymap.set({ "n", "x" }, "<leader>d", '"_d', { desc = "Delete without overriding clipboard" })

	-- Delete character under cursor without overriding clipboard
	vim.keymap.set("n", "x", '"_x')

	-- Open Mason
	vim.keymap.set("n", "<leader>m", "<cmd>lua require('util.keymaps').open_mason()<cr>", { desc = "Open Mason" })

	-- Open Lazy
	vim.keymap.set("n", "<leader>l", "<cmd>lua require('util.keymaps').open_lazy()<cr>", { desc = "Open Lazy" })

	-- Exit terminal mode in the builtin terminal with a shortcut that is easier
	vim.keymap.set("t", "<esc><esc>", "<c-\\><c-n>", { desc = "Exit terminal mode" })

	-- Keep selection when indenting
	vim.keymap.set("x", ">", ">gv")
	vim.keymap.set("x", "<", "<gv")

	-- Map / to search for selected text in visual mode
	vim.keymap.set("x", "/", 'y/\\V<c-r>=v:lua.require("util.keymaps").escape_term(@")<cr><cr>')

	-- Map ? to search backward for selected text in visual mode
	vim.keymap.set("x", "?", 'y?\\V<c-r>=v:lua.require("util.keymaps").escape_term(@")<cr><cr>')

	-- Properly position cursor when searching and open closed folds
	vim.keymap.set("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
	vim.keymap.set("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
	vim.keymap.set("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
	vim.keymap.set("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
	vim.keymap.set("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })
	vim.keymap.set("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

	-- Start new undo block when entering any of these characters
	vim.keymap.set("i", ",", ",<c-g>u")
	vim.keymap.set("i", ".", ".<c-g>u")
	vim.keymap.set("i", ";", ";<c-g>u")

	-- Buffers
	vim.keymap.set("n", "]b", "<cmd>bnext<cr>", { desc = "Next Buffer" })
	vim.keymap.set("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
	vim.keymap.set("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })
	vim.keymap.set("n", "<leader>bd", "<cmd>lua require('util.keymaps').bufremove()<cr>", { desc = "Delete Buffer" })
	vim.keymap.set("n", "<leader>bD", "<cmd>bd<cr>", { desc = "Delete Buffer and Window" })

	-- New file
	vim.keymap.set("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New File" })

	-- Quickfix
	vim.keymap.set("n", "[q", vim.cmd.cprev, { desc = "Prev Quickfix" })
	vim.keymap.set("n", "]q", vim.cmd.cnext, { desc = "Next Quickfix" })

	-- Diagnostics
	vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })
	vim.keymap.set(
		"n",
		"]d",
		"<cmd>lua vim.diagnostic.jump({ count = 1, float = true })<cr>",
		{ desc = "Next Diagnostic" }
	)
	vim.keymap.set(
		"n",
		"[d",
		"<cmd>lua vim.diagnostic.jump({ count = -1, float = true })<cr>",
		{ desc = "Prev Diagnostic" }
	)

	-- Marks
	vim.keymap.set("n", "dm", "<cmd>lua require('util.keymaps').delmarks()<cr>", { desc = "Delete Marks" })

	-- Disable tab keymaps
	vim.keymap.set("n", "gt", "<nop>", { desc = "" })
	vim.keymap.set("n", "gT", "<nop>", { desc = "" })

	-- Format
	vim.keymap.set(
		{ "n", "v" },
		"<leader>cf",
		"<cmd>lua require('plugins.conform').formatexpr()<cr>",
		{ desc = "Format" }
	)

	-- Lint
	vim.keymap.set({ "n", "x" }, "<leader>cl", "<cmd>lua require('plugins.lint').try_lint()<cr>", { desc = "Lint" })

	-- Windows
	vim.keymap.set("n", "<leader>w", "<c-w>", { desc = "Windows", remap = true })
	vim.keymap.set("n", "<c-w>-", "<c-w>s", { desc = "Split Window Below", remap = true })
	vim.keymap.set("n", "<c-w>=", "<c-w>v", { desc = "Split Window Right", remap = true })
	vim.keymap.set("n", "<c-w>d", "<c-w>c", { desc = "Delete Window", remap = true })
	vim.keymap.set("n", "<leader>wm", "<cmd>lua require('util.keymaps').maximize()<cr>", { desc = "Maximise Window" })

	-- Git
	vim.keymap.set("n", "<leader>gg", "<cmd>lua require('util.keymaps').open_git()<cr>", { desc = "Git Menu" })
	vim.keymap.set(
		"n",
		"<leader>gf",
		"<cmd>lua require('util.keymaps').open_git_file_commits()<cr>",
		{ desc = "Git File Commits Log" }
	)
	vim.keymap.set(
		"n",
		"<leader>gB",
		"<cmd>lua require('util.keymaps').open_git_blame()<cr>",
		{ desc = "Git Blame Log" }
	)

	-- User interface
	vim.keymap.set(
		"n",
		"<leader>ui",
		"<cmd>lua require('util.keymaps').toggle_signs()<cr>",
		{ desc = "User Interface Signs" }
	)
end

-- LSP
function M.lsp(buffer)
	vim.keymap.set("n", "<leader>cl", "<cmd>LspInfo<cr>", { buffer = buffer, desc = "Lsp Info" })
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = buffer, desc = "Goto Definition" })
	vim.keymap.set("n", "gr", vim.lsp.buf.references, { buffer = buffer, desc = "References" })
	vim.keymap.set("n", "gI", vim.lsp.buf.implementation, { buffer = buffer, desc = "Goto Implementation" })
	vim.keymap.set("n", "gy", vim.lsp.buf.type_definition, { buffer = buffer, desc = "Goto Type Definition" })
	vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = buffer, desc = "Goto Declaration" })
	vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = buffer, desc = "Hover" })
	vim.keymap.set("i", "<c-k>", vim.lsp.buf.signature_help, { buffer = buffer, desc = "Signature Help" })
	vim.keymap.set("n", "crr", vim.lsp.buf.code_action, { buffer = buffer, desc = "Code Action" })
	vim.keymap.set("n", "<leader>cc", vim.lsp.codelens.run, { buffer = buffer, desc = "Run Codelens" })
	vim.keymap.set(
		"n",
		"<leader>cC",
		vim.lsp.codelens.refresh,
		{ buffer = buffer, desc = "Refresh & Display Codelens" }
	)
	vim.keymap.set("n", "crn", vim.lsp.buf.rename, { buffer = buffer, desc = "Rename" })
	-- vim.keymap.set("n", "<leader>cr", LazyVim.lsp.rename_file, { buffer = buffer, desc = "Rename File" })
	-- vim.keymap.set("n", "<leader>cA", LazyVim.lsp.action.source, { buffer = buffer, desc = "Source Action" })
	-- vim.keymap.set("n", "]]", function()
	-- 	LazyVim.lsp.words.jump(vim.v.count1)
	-- end, { buffer = buffer, desc = "Next Reference" })
	-- vim.keymap.set("n", "[[", function()
	-- 	LazyVim.lsp.words.jump(-vim.v.count1)
	-- end, { buffer = buffer, desc = "Prev Reference" })
	-- vim.keymap.set("n", "<a-n>", function()
	-- 	LazyVim.lsp.words.jump(vim.v.count1, true)
	-- end, { buffer = buffer, desc = "Next Reference" })
	-- vim.keymap.set("n", "<a-p>", function()
	-- 	LazyVim.lsp.words.jump(-vim.v.count1, true)
	-- end, { buffer = buffer, desc = "Prev Reference" })
end

return M
