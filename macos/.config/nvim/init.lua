-- luacheck: globals vim

-- ********************************************************************************
-- * Globals                                                                      *
-- ********************************************************************************

-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Set bigfile size to 1MB
vim.g.bigfile_size = 1024 * 1024

-- Show marks in the sign column
vim.g.show_marks = true

-- Show diagnostics in the sign column
vim.g.show_diagnostics = true

-- ********************************************************************************
-- * Functions                                                                    *
-- ********************************************************************************

-- Function to create folds
local skip_foldexpr = {}
local skip_check = assert(vim.uv.new_check())

_G.foldexpr = function()
	local buf = vim.api.nvim_get_current_buf()
	if skip_foldexpr[buf] then
		return "0"
	end
	if vim.bo[buf].buftype ~= "" then
		return "0"
	end
	if vim.bo[buf].filetype == "" then
		return "0"
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
	return "0"
end

local function get_signs(buf, lnum)
	local signs = {}
	local extmarks = vim.api.nvim_buf_get_extmarks(
		buf,
		-1,
		{ lnum - 1, 0 },
		{ lnum - 1, -1 },
		{ details = true, type = "sign" }
	)
	for _, extmark in pairs(extmarks) do
		signs[#signs + 1] = {
			name = extmark[4].sign_hl_group or extmark[4].sign_name or "",
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
		if mark.pos[1] == buf and mark.pos[2] == lnum and mark.mark:match("[a-zA-Z]") then
			return { text = mark.mark:sub(2), texthl = "DiagnosticHint" }
		end
	end
end

local function get_icon(sign, len)
	sign = sign or {}
	len = len or 2
	local text = vim.fn.strcharpart(sign.text or "", 0, len)
	text = text .. string.rep(" ", len - vim.fn.strchars(text))
	return sign.texthl and ("%#" .. sign.texthl .. "#" .. text .. "%*") or text
end

_G.signcolumn = function()
	local win = vim.g.statusline_winid
	local buf = vim.api.nvim_win_get_buf(win)
	local is_file = vim.bo[buf].buftype == ""
	local components = { "", "", "" }
	local signs = get_signs(buf, vim.v.lnum)
	local left, right, fold, githl
	for _, s in ipairs(signs) do
		if s.name and s.name:find("GitSign") then
			right = s
			githl = s["texthl"]
		else
			left = s
		end
	end
	vim.api.nvim_win_call(win, function()
		if vim.fn.foldclosed(vim.v.lnum) >= 0 then
			fold = { text = vim.opt.fillchars:get().foldclose or "", texthl = githl or "Folded" }
		end
	end)
	if vim.g.show_marks then
		components[1] = get_icon(get_mark(buf, vim.v.lnum) or left)
	end
	components[3] = is_file and get_icon(fold or right) or ""
	if vim.v.virtnum == 0 then
		components[2] = "%l"
		components[2] = "%=" .. components[2] .. " "
	end
	if vim.v.virtnum ~= 0 then
		components[2] = "%= "
	end
	return table.concat(components, "")
end

-- Function to escape special characters for search
_G.escape_term = function(term)
	return vim.fn.escape(term, "/\\")
end

-- Function to remove buffer without closing window
local function bufremove(buf)
	buf = buf or 0
	buf = buf == 0 and vim.api.nvim_get_current_buf() or buf

	if vim.bo.modified then
		local choice = vim.fn.confirm(("Save changes to %q?"):format(vim.fn.bufname()), "&Yes\n&No\n&Cancel")
		if choice == 0 or choice == 3 then
			return
		end
		if choice == 1 then
			vim.cmd.write()
		end
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.api.nvim_win_call(win, function()
			if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
				return
			end
			local alt = vim.fn.bufnr("#")
			if alt ~= buf and vim.fn.buflisted(alt) == 1 then
				vim.api.nvim_win_set_buf(win, alt)
				return
			end
			local has_previous = pcall(vim.cmd, "bprevious")
			if has_previous and buf ~= vim.api.nvim_win_get_buf(win) then
				return
			end
			local new_buf = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_win_set_buf(win, new_buf)
		end)
	end
	if vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.cmd, "bdelete! " .. buf)
	end
end

-- Function to delete marks on the current line
local function delmarks()
	local current_line = vim.fn.line(".")
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
			vim.cmd("delmarks " .. mark)
		end
	end
end

-- Is a float open
local float_open = false

-- Open Lazy
local function open_lazy()
	if not float_open then
		float_open = true
		vim.cmd("Lazy")
	end
end

-- Open Mason
local function open_mason()
	if not float_open then
		float_open = true
		vim.cmd("Mason")
	end
end

-- Git in floating window
local function open_git(command, lazygit)
	if float_open then
		return
	end
	float_open = true
	if not lazygit then
		require("lazy.util").float_cmd(command, {
			filetype = "git",
			size = {
				width = 0.85,
				height = 0.85,
			},
			border = "rounded",
		})
	else
		local width = math.ceil(vim.o.columns * 0.85)
		local height = math.ceil(vim.o.lines * 0.85)
		local left = math.ceil((vim.o.columns - width) / 2)
		local top = math.ceil((vim.o.lines - height) / 2)
		local buf = vim.api.nvim_create_buf(false, true)
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = top,
			col = left,
			style = "minimal",
		})
		vim.keymap.set("t", "<esc>", "<esc>", { buffer = buf, nowait = true })
		command = table.concat(command, " ")
		vim.fn.termopen(command, {
			on_exit = function()
				vim.api.nvim_win_close(win, true)
			end,
		})
		vim.bo.filetype = "git"
		vim.cmd("startinsert")
	end
end

-- Maximize window
local is_maximized = false
local previous_options = {}

local function toggle_maximize()
	if is_maximized then
		for _, opt in ipairs(previous_options) do
			vim.o[opt.k] = opt.v
		end
		previous_options = {}
		vim.cmd("wincmd =")
		is_maximized = false
	else
		local function save(k)
			table.insert(previous_options, 1, { k = k, v = vim.o[k] })
		end
		save("winwidth")
		save("winheight")
		save("winminwidth")
		save("winminheight")
		vim.o.winwidth = 999
		vim.o.winheight = 999
		vim.o.winminwidth = 10
		vim.o.winminheight = 4
		vim.cmd("wincmd =")
		vim.api.nvim_create_autocmd("ExitPre", {
			once = true,
			group = vim.api.nvim_create_augroup("toggle_maximize", { clear = true }),
			desc = "Restore width/height when close Neovim while maximized",
			callback = function()
				toggle_maximize()
			end,
		})
		is_maximized = true
	end
end

-- Toggle signs in sign column
local function toggle_signs()
	vim.cmd("Gitsigns toggle_signs")
	vim.g.show_marks = not vim.g.show_marks
	if vim.g.show_diagnostics then
		vim.diagnostic.hide()
		vim.g.show_diagnostics = false
	else
		vim.diagnostic.show()
		vim.g.show_diagnostics = true
	end
end

-- ********************************************************************************
-- * Options                                                                      *
-- ********************************************************************************

-- Make line numbers default
vim.opt.number = true

-- Add relative line numbers, to help with jumping
vim.opt.relativenumber = true

-- Set the number of spaces that a <Tab> in the file counts for
vim.opt.tabstop = 2

-- Number of spaces a <Tab> counts for while editing
vim.opt.softtabstop = 2

-- Set the number of spaces to use for each step of (auto)indent
vim.opt.shiftwidth = 2

-- Round indent to multiple of shift width
vim.opt.shiftround = true

-- Convert tabs to spaces
vim.opt.expandtab = true

-- Enable mouse mode, can be useful for resizing splits
vim.opt.mouse = "a"

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Save undo history
vim.opt.undofile = true

-- Save as many undo ops as possible
vim.opt.undolevels = 10000

-- Save to swap file after 200ms
vim.opt.updatetime = 200

-- Case-insensitive searching one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Disable line wrapping
vim.opt.wrap = false

-- Better line wrapping
vim.opt.linebreak = true

-- Keep the sign column on by default
vim.opt.signcolumn = "yes"

-- Decrease update time
vim.opt.updatetime = 50

-- Decrease mapped sequence wait time, displays which-key popup sooner
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Maintain text around the cursor when splitting
vim.opt.splitkeep = "screen"

-- Preview substitutions live, as you type!
vim.opt.inccommand = "split"

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 13

-- Same as scrolloff, but for the horizontal axis
vim.opt.sidescrolloff = 13

-- Enable highlight on search
vim.opt.hlsearch = true

-- Enables incremental search, highlights matches while typing
vim.opt.incsearch = true

-- Set the command line height to 0, to disable it when not in use
vim.opt.cmdheight = 0

-- Maximum number of items in the popup menu
vim.opt.pumheight = 10

-- Blend the popup menu with the background
vim.opt.pumblend = 10

-- Auto save when focus is lost
vim.opt.autowrite = true

-- Set completion options
vim.opt.completeopt = "menu,menuone,noselect"

-- Hide * markup for bold and italic, but not markers with substitutions
vim.opt.conceallevel = 2

-- Spellcheck
vim.opt.spelllang = { "en" }

-- Confirm instead of failing
vim.opt.confirm = true

-- Set fill characters
vim.opt.fillchars = {
	foldopen = "",
	foldclose = "",
	fold = " ",
	foldsep = " ",
	diff = "╱",
	eob = " ",
}

-- Open all folds when file is opened
vim.opt.foldlevel = 99

-- Set the format options
vim.opt.formatoptions = "jcroqlnt"

-- Set the grep format
vim.opt.grepformat = "%f:%l:%c:%m"

-- Use ripgrep for grepping
vim.opt.grepprg = "rg --vimgrep"

-- Preview search/replace in buffer
vim.opt.inccommand = "nosplit"

-- Keep view when jumping
vim.opt.jumpoptions = "view"

-- Set mimimum width
vim.opt.winminwidth = 5

-- Single status line across splits
vim.opt.laststatus = 3

-- Store more information in the session file
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

-- Disable vim info messages
vim.opt.shortmess:append({ W = true, I = true, c = true, C = true })

-- Automatic indenting new lines
vim.opt.smartindent = true

-- True color support
vim.opt.termguicolors = true

-- Set a short timeout length for which-key
vim.opt.timeoutlen = 300

-- Move cursor freely in visual block
vim.opt.virtualedit = "block"

-- Set command-line completion mode
vim.opt.wildmode = "longest:full,full"

-- Enable smooth scrolling
vim.opt.smoothscroll = true

-- Set status column
vim.opt.statuscolumn = [[%!v:lua.signcolumn()]]

-- Create folds using expressions
vim.opt.foldexpr = "v:lua.foldexpr()"
vim.opt.foldmethod = "expr"

-- Disable fold text
vim.opt.foldtext = ""

-- Disable tabs
vim.opt.showtabline = 0

-- ********************************************************************************
-- * Keymaps                                                                      *
-- ********************************************************************************

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
vim.keymap.set("n", "<char-0xe0>", function()
	require("smart-splits").move_cursor_left()
end)
vim.keymap.set("n", "<char-0xe1>", function()
	require("smart-splits").move_cursor_down()
end)
vim.keymap.set("n", "<char-0xe2>", function()
	require("smart-splits").move_cursor_up()
end)
vim.keymap.set("n", "<char-0xe3>", function()
	require("smart-splits").move_cursor_right()
end)

-- Resize window using ctrl + super + hjkl keys
vim.keymap.set("n", "<Char-0xe4>", function()
	require("smart-splits").resize_left()
end)
vim.keymap.set("n", "<Char-0xe5>", function()
	require("smart-splits").resize_down()
end)
vim.keymap.set("n", "<Char-0xe6>", function()
	require("smart-splits").resize_up()
end)
vim.keymap.set("n", "<Char-0xe7>", function()
	require("smart-splits").resize_right()
end)

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
vim.keymap.set("n", "<leader>m", open_mason, { desc = "Open Mason" })

-- Open Lazy
vim.keymap.set("n", "<leader>l", open_lazy, { desc = "Open Lazy" })

-- Exit terminal mode in the builtin terminal with a shortcut that is easier
vim.keymap.set("t", "<esc><esc>", "<c-\\><c-n>", { desc = "Exit terminal mode" })

-- Keep selection when indenting
vim.keymap.set("x", ">", ">gv")
vim.keymap.set("x", "<", "<gv")

-- Map / to search for selected text in visual mode
vim.keymap.set("x", "/", 'y/\\V<c-r>=v:lua.escape_term(@")<cr><cr>')

-- Map ? to search backward for selected text in visual mode
vim.keymap.set("x", "?", 'y?\\V<c-r>=v:lua.escape_term(@")<cr><cr>')

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
vim.keymap.set("n", "<leader>bd", bufremove, { desc = "Delete Buffer" })
vim.keymap.set("n", "<leader>bD", "<cmd>:bd<cr>", { desc = "Delete Buffer and Window" })

-- New file
vim.keymap.set("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New File" })

-- Quickfix
vim.keymap.set("n", "[q", vim.cmd.cprev, { desc = "Prev Quickfix" })
vim.keymap.set("n", "]q", vim.cmd.cnext, { desc = "Next Quickfix" })

-- Diagnostics
vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })
vim.keymap.set("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next Diagnostic" })
vim.keymap.set("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Prev Diagnostic" })

-- Marks
vim.keymap.set("n", "dm", delmarks, { desc = "Delete Marks" })

-- Disable tab keymaps
vim.keymap.set("n", "gt", "<nop>", { desc = "" })
vim.keymap.set("n", "gT", "<nop>", { desc = "" })

-- Format
vim.keymap.set({ "n", "v" }, "<leader>cf", function()
	require("conform").formatexpr()
end, { desc = "Format" })

-- Lint
vim.keymap.set({ "n", "x" }, "<leader>cl", function()
	require("lint").try_lint()
end, { desc = "Lint" })

-- Windows
vim.keymap.set("n", "<leader>w", "<c-w>", { desc = "Windows", remap = true })
vim.keymap.set("n", "<c-w>-", "<c-w>s", { desc = "Split Window Below", remap = true })
vim.keymap.set("n", "<c-w>=", "<c-w>v", { desc = "Split Window Right", remap = true })
vim.keymap.set("n", "<c-w>d", "<c-w>c", { desc = "Delete Window", remap = true })
vim.keymap.set("n", "<leader>wm", toggle_maximize, { desc = "Maximise Window" })

-- Lazygit
vim.keymap.set("n", "<leader>gg", function()
	open_git({ "lazygit" }, true)
end, { desc = "Git Menu" })
vim.keymap.set("n", "<leader>gf", function()
	local file = vim.api.nvim_buf_get_name(0)
	local command = { "lazygit", "-f", vim.trim(file) }
	open_git(command, true)
end, { desc = "Git File Commits Log" })
vim.keymap.set("n", "<leader>gB", function()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local file = vim.api.nvim_buf_get_name(0)

	local function root()
		local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
		if handle == nil then
			return "."
		else
			local result = handle:read("*a"):gsub("%s+$", "")
			handle:close()
			return result
		end
	end
	local command = { "git", "-C", root(), "log", "-u", "-L", line .. ",+1:" .. file }
	open_git(command, false)
end, { desc = "Git Blame Log" })

-- User interface
vim.keymap.set("n", "<leader>ui", toggle_signs, { desc = "User Interface Signs" })

-- LSP
local function lsp_keymaps(buffer)
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

-- ********************************************************************************
-- * Autocommands                                                                 *
-- ********************************************************************************

-- Check if file was changed outside of Neovim
vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
	group = vim.api.nvim_create_augroup("checktime", { clear = true }),
	callback = function()
		if vim.o.buftype ~= "nofile" then
			vim.cmd("checktime")
		end
	end,
})

-- Highlight when yanking text
vim.api.nvim_create_autocmd("TextYankPost", {
	group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

-- Disable relative line numbers when in insert mode
local relativenumber_group = vim.api.nvim_create_augroup("relativenumber", { clear = true })

vim.api.nvim_create_autocmd("InsertEnter", {
	group = relativenumber_group,
	callback = function()
		local is_file = vim.bo.buftype == ""
		if is_file then
			vim.opt.relativenumber = false
		end
	end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
	group = relativenumber_group,
	callback = function()
		local is_file = vim.bo.buftype == ""
		if is_file then
			vim.opt.relativenumber = true
		end
	end,
})

-- Disable line numbers when in terminal mode
vim.api.nvim_create_autocmd("TermOpen", {
	group = vim.api.nvim_create_augroup("terminal", { clear = true }),
	callback = function()
		vim.opt.number = false
		vim.opt.relativenumber = false
	end,
})

-- Prevent automatic comments on new lines
vim.api.nvim_create_autocmd("BufEnter", {
	group = vim.api.nvim_create_augroup("no_auto_comment", { clear = true }),
	pattern = "",
	command = "set fo-=c fo-=r fo-=o",
})

-- Remove trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
	group = vim.api.nvim_create_augroup("remove_trailing_whitespace", { clear = true }),
	pattern = "*",
	command = ":%s/\\s\\+$//e",
})

-- Auto save on buffer leave or focus lost
vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
	group = vim.api.nvim_create_augroup("auto_save", { clear = true }),
	command = [[if &modified && !&readonly && expand("%") != "" && &buftype == "" | silent! update | endif]],
})

-- Resize splits when resizing window
vim.api.nvim_create_autocmd("VimResized", {
	group = vim.api.nvim_create_augroup("resize_splits", { clear = true }),
	pattern = "*",
	command = "wincmd =",
})

-- Close Lazy with <esc>
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("close_lazy", { clear = true }),
	pattern = "lazy",
	callback = function()
		vim.keymap.set("n", "<esc>", function()
			vim.api.nvim_win_close(0, false)
		end, { buffer = true, nowait = true })
	end,
})

-- Make sure open float is false when leaving a foating window
vim.api.nvim_create_autocmd("BufLeave", {
	group = vim.api.nvim_create_augroup("float_open", { clear = true }),
	callback = function()
		local ft = vim.bo.filetype
		if ft == "lazy" or ft == "mason" or ft == "git" then
			float_open = false
		end
	end,
})

-- Go to last loc when opening a buffer
vim.api.nvim_create_autocmd("BufReadPost", {
	group = vim.api.nvim_create_augroup("last_loc", { clear = true }),
	callback = function(event)
		local exclude = { "gitcommit" }
		local buf = event.buf
		if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].lazyvim_last_loc then
			return
		end
		vim.b[buf].lazyvim_last_loc = true
		local mark = vim.api.nvim_buf_get_mark(buf, '"')
		local lcount = vim.api.nvim_buf_line_count(buf)
		if mark[1] > 0 and mark[1] <= lcount then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- Close some filetypes with <q>
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("close_with_q", { clear = true }),
	pattern = {
		"PlenaryTestPopup",
		"help",
		"lspinfo",
		"qf",
		"spectre_panel",
		"tsplayground",
		"neotest-output",
		"checkhealth",
		"neotest-summary",
		"neotest-output-panel",
		"dbout",
		"gitsigns.blame",
	},
	callback = function(event)
		vim.bo[event.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<cr>", {
			buffer = event.buf,
			silent = true,
			desc = "Quit buffer",
		})
	end,
})

-- Make it easier to close man-files when opened inline
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("man_unlisted", { clear = true }),
	pattern = { "man" },
	callback = function(event)
		vim.bo[event.buf].buflisted = false
	end,
})

-- Wrap and check for spell in text filetypes
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("wrap_spell", { clear = true }),
	pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

-- Fix conceallevel for json files
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("json_conceal", { clear = true }),
	pattern = { "json", "jsonc", "json5" },
	callback = function()
		vim.opt_local.conceallevel = 0
	end,
})

-- Auto create dir when saving a file, in case some intermediate directory does not exist
vim.api.nvim_create_autocmd("BufWritePre", {
	group = vim.api.nvim_create_augroup("auto_create_dir", { clear = true }),
	callback = function(event)
		if event.match:match("^%w%w+:[\\/][\\/]") then
			return
		end
		local file = vim.uv.fs_realpath(event.match) or event.match
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
	end,
})

-- Set filetype to bigfile for large files
vim.filetype.add({
	pattern = {
		[".*"] = {
			function(path, buf)
				return vim.bo[buf]
						and vim.bo[buf].filetype ~= "bigfile"
						and path
						and vim.fn.getfsize(path) > vim.g.bigfile_size
						and "bigfile"
					or nil
			end,
		},
	},
})

-- ********************************************************************************
-- * Package manager                                                              *
-- ********************************************************************************

-- Clone the Lazy plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Lazy configuration
local lazy_config = {
	install = { colorscheme = { "catppuccin-mocha" } },
	checker = { enabled = true },
	ui = {
		size = { width = 0.85, height = 0.85 },
		border = "rounded",
		wrap = false,
		backdrop = 100,
		icons = {
			lazy = "",
		},
	},
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip",
				"netrwPlugin",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
			},
		},
	},
}

-- Setup plugins table
local plugins = {}

-- ********************************************************************************
-- * Colorscheme                                                                  *
-- ********************************************************************************

-- Set colorscheme
table.insert(plugins, {
	"catppuccin/nvim",
	name = "catppuccin",
	priority = 1000,
	opts = {
		flavor = "mocha",
		default_integrations = false,
		term_colors = true,
		integrations = {
			treesitter = true,
			treesitter_context = true,
			harpoon = true,
			mini = true,
			cmp = true,
			which_key = true,
			gitsigns = true,
			indent_blankline = {
				enabled = true,
			},
			mason = true,
			neotest = true,
			lsp_trouble = true,
			native_lsp = {
				enabled = true,
				virtual_text = {
					errors = { "italic" },
					hints = { "italic" },
					warnings = { "italic" },
					information = { "italic" },
				},
				underlines = {
					errors = { "undercurl" },
					hints = { "undercurl" },
					warnings = { "undercurl" },
					information = { "undercurl" },
				},
				inlay_hints = {
					background = true,
				},
			},
		},
	},
	config = function(_, opts)
		require("catppuccin").setup(opts)
		vim.cmd.colorscheme("catppuccin-mocha")
	end,
})

-- ********************************************************************************
-- * Treesitter                                                                   *
-- ********************************************************************************

-- Keymaps for treesitter
table.insert(plugins, {
	"folke/which-key.nvim",
	opts = {
		spec = {
			{ "<BS>", desc = "Decrement Selection", mode = "x" },
			{ "<c-space>", desc = "Increment Selection", mode = { "x", "n" } },
		},
	},
})

-- Treesitter
table.insert(plugins, {
	"nvim-treesitter/nvim-treesitter",
	version = false,
	build = ":TSUpdate",
	event = { "BufReadPre", "BufNewFile" },
	lazy = vim.fn.argc(-1) == 0,
	init = function(plugin)
		require("lazy.core.loader").add_to_rtp(plugin)
		require("nvim-treesitter.query_predicates")
	end,
	cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
	keys = {
		{ "<c-space>", desc = "Increment Selection" },
		{ "<bs>", desc = "Decrement Selection", mode = "x" },
	},
	opts_extend = { "ensure_installed" },
	opts = {
		highlight = { enable = true },
		indent = { enable = true },
		ensure_installed = {
			"bash",
			"c",
			"diff",
			"html",
			"javascript",
			"jsdoc",
			"json",
			"jsonc",
			"lua",
			"luadoc",
			"luap",
			"markdown",
			"markdown_inline",
			"printf",
			"python",
			"query",
			"regex",
			"toml",
			"tsx",
			"typescript",
			"vim",
			"vimdoc",
			"xml",
			"yaml",
		},
		incremental_selection = {
			enable = true,
			keymaps = {
				init_selection = "<C-space>",
				node_incremental = "<C-space>",
				scope_incremental = false,
				node_decremental = "<bs>",
			},
		},
		textobjects = {
			move = {
				enable = true,
				goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
				goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
				goto_previous_start = {
					["[f"] = "@function.outer",
					["[c"] = "@class.outer",
					["[a"] = "@parameter.inner",
				},
				goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
			},
		},
	},
	config = function(_, opts)
		require("nvim-treesitter.configs").setup(opts)
	end,
})

-- Text objects for treesitter
table.insert(plugins, {
	"nvim-treesitter/nvim-treesitter-textobjects",
	event = "VeryLazy",
	enabled = true,
	config = function()
		if require("lazy.core.config").plugins["nvim-treesitter"]._.loaded then
			local plugin = require("lazy.core.config").spec.plugins["nvim-treesitter"]
			local opts = require("lazy.core.plugin").values(plugin, "opts", false)
			require("nvim-treesitter.configs").setup({ textobjects = opts.textobjects })
		end
		local move = require("nvim-treesitter.textobjects.move")
		local configs = require("nvim-treesitter.configs")
		for name, fn in pairs(move) do
			if name:find("goto") == 1 then
				move[name] = function(q, ...)
					if vim.wo.diff then
						local config = configs.get_module("textobjects.move")[name]
						for key, query in pairs(config or {}) do
							if q == query and key:find("[%]%[][cC]") then
								vim.cmd("normal! " .. key)
								return
							end
						end
					end
					return fn(q, ...)
				end
			end
		end
	end,
})

-- Automatically add closing tags for HTML and JSX
table.insert(plugins, {
	"windwp/nvim-ts-autotag",
	event = { "BufReadPre", "BufNewFile" },
	opts = {},
})

-- ********************************************************************************
-- * Language Servers                                                             *
-- ********************************************************************************

-- Lspconfig
table.insert(plugins, {
	"neovim/nvim-lspconfig",
	event = "LazyFile",
	dependencies = {
		"williamboman/mason.nvim",
		{ "williamboman/mason-lspconfig.nvim", config = function() end },
	},
	opts = {
		diagnostics = {
			underline = true,
			update_in_insert = false,
			virtual_text = {
				spacing = 4,
				source = "if_many",
				prefix = "●",
			},
			severity_sort = true,
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = "",
					[vim.diagnostic.severity.WARN] = "",
					[vim.diagnostic.severity.HINT] = "",
					[vim.diagnostic.severity.INFO] = "",
				},
			},
		},
		inlay_hints = {
			enabled = true,
		},
		codelens = {
			enabled = false,
		},
		document_highlight = {
			enabled = true,
		},
		capabilities = {
			workspace = {
				fileOperations = {
					didRename = true,
					willRename = true,
				},
			},
		},
		format = {
			formatting_options = nil,
			timeout_ms = nil,
		},
		servers = {
			lua_ls = {
				settings = {
					Lua = {
						workspace = {
							checkThirdParty = false,
						},
						codeLens = {
							enable = true,
						},
						completion = {
							callSnippet = "Replace",
						},
						doc = {
							privateName = { "^_" },
						},
						hint = {
							enable = true,
							setType = false,
							paramType = true,
							paramName = "Disable",
							semicolon = "Disable",
							arrayIndex = "Disable",
						},
					},
				},
			},
		},
		setup = {},
	},
	config = function(_, opts)
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(event)
				lsp_keymaps(event.buf)
			end,
		})
		for severity, icon in pairs(opts.diagnostics.signs.text) do
			local name = vim.diagnostic.severity[severity]:lower():gsub("^%l", string.upper)
			name = "DiagnosticSign" .. name
			vim.fn.sign_define(name, { text = icon, texthl = name, numhl = "" })
		end
		vim.diagnostic.config({
			underline = true,
			update_in_insert = false,
			virtual_text = {
				spacing = 4,
				source = "if_many",
				prefix = "●",
			},
			severity_sort = true,
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = "",
					[vim.diagnostic.severity.WARN] = "",
					[vim.diagnostic.severity.HINT] = "",
					[vim.diagnostic.severity.INFO] = "",
				},
			},
		})

		local capabilities = require("cmp_nvim_lsp").default_capabilities()
		local default_setup = function(server)
			require("lspconfig")[server].setup({
				capabilities = capabilities,
			})
		end
		require("mason-lspconfig").setup({
			handlers = {
				default_setup,
				lua_ls = function()
					require("lspconfig").lua_ls.setup({
						capabilities = capabilities,
					})
				end,
			},
			automatic_installation = true,
			ensure_installed = {
				"lua_ls",
				"vtsls",
				"html",
				"tailwindcss",
				"pyright",
				"angularls",
				"bashls",
				"omnisharp",
				"cssls",
				"dockerls",
				"docker_compose_language_service",
				"gradle_ls",
				"jsonls",
				"jdtls",
				"kotlin_language_server",
				"ltex",
				"markdown_oxide",
				"sqlls",
				"yamlls",
			},
		})
	end,
})

-- Cmdline tools and lsp servers
table.insert(plugins, {
	"williamboman/mason.nvim",
	cmd = "Mason",
	build = ":MasonUpdate",
	opts_extend = { "ensure_installed" },
	opts = {
		ui = {
			width = 0.85,
			height = 0.85,
			border = "rounded",
			icons = {
				package_installed = "●",
				package_pending = "➜",
				package_uninstalled = "○",
			},
			keymaps = {
				uninstall_package = "x",
				toggle_help = "?",
			},
		},
		ensure_installed = {
			"stylua",
			"shfmt",
		},
	},
	config = function(_, opts)
		require("mason").setup(opts)
		local registry = require("mason-registry")
		registry:on("package:install:success", function()
			vim.defer_fn(function()
				require("lazy.core.handler.event").trigger({
					event = "FileType",
					buf = vim.api.nvim_get_current_buf(),
				})
			end, 100)
		end)
		registry.refresh(function()
			for _, tool in ipairs(opts.ensure_installed) do
				local p = registry.get_package(tool)
				if not p:is_installed() then
					p:install()
				end
			end
		end)
	end,
})

-- ********************************************************************************
-- * Coding                                                                       *
-- ********************************************************************************
-- Development config
table.insert(plugins, {
	"folke/lazydev.nvim",
	depdendencies = {
		"justinsgithub/wezterm-types",
	},
	ft = "lua",
	opts = {
		library = {
			{ path = "wezterm-types", mods = { "wezterm" } },
		},
	},
})

-- ********************************************************************************
-- * Editor                                                                       *
-- ********************************************************************************

-- Smart Splits
table.insert(plugins, {
	"mrjones2014/smart-splits.nvim",
	opts = {},
})

-- ********************************************************************************
-- * Linting & Formatting                                                         *
-- ********************************************************************************

-- Conform
table.insert(plugins, {
	"stevearc/conform.nvim",
	dependencies = { "LittleEndianRoot/mason-conform" },
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		require("conform").setup({
			format_on_save = {
				timeout_ms = 3000,
				lsp_fallback = true,
			},
			formatters_by_ft = {
				lua = { "stylua" },
				javascript = { "prettierd" },
				typescript = { "prettierd" },
				typescriptreact = { "prettierd" },
				javascriptreact = { "prettierd" },
				html = { "prettierd" },
				css = { "prettierd" },
				json = { "prettierd" },
				jsonc = { "prettierd" },
				markdown = { "prettierd" },
				python = { "black" },
				sh = { "shfmt" },
				yaml = { "prettierd" },
				toml = { "prettierd" },
				sql = { "sql-formatter" },
				java = { "google-java-format" },
				kotlin = { "ktlint" },
				zsh = { "shfmt" },
			},
		})
		vim.keymap.set({ "n", "x" }, "<leader>cf", function()
			require("conform").format({
				timeout_ms = 2000,
				lsp_fallback = true,
			})
		end, { desc = "Format file or range (in visual mode)" })
		require("mason-conform").setup({
			automatic_installation = false,
			ensure_installed = {
				"stylua",
				"prettierd",
				"black",
				"shfmt",
				"sql-formatter",
				"google-java-format",
				"ktlint",
			},
		})
	end,
})

-- Nvim Lint
table.insert(plugins, {
	"mfussenegger/nvim-lint",
	dependencies = { "rshkarin/mason-nvim-lint" },
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			lua = { "luacheck" },
			javascript = { "eslint_d" },
			typescript = { "eslint_d" },
			typescriptreact = { "eslint_d" },
			javascriptreact = { "eslint_d" },
			html = { "htmlhint" },
			css = { "stylelint" },
			json = { "jsonlint" },
			jsonc = { "jsonlint" },
			markdown = { "markdownlint" },
			python = { "flake8" },
			sh = { "shellcheck" },
			yaml = { "yamllint" },
			sql = { "sqlfluff" },
			java = { "checkstyle" },
			kotlin = { "ktlint" },
			zsh = { "shellcheck" },
		}
		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave", "TextChanged" }, {
			callback = function()
				lint.try_lint()
			end,
		})
		vim.keymap.set({ "n", "x" }, "<leader>cl", lint.try_lint, { desc = "Lint file" })
		require("mason-nvim-lint").setup({
			automatic_installation = false,
			ensure_installed = {
				"luacheck",
				"eslint_d",
				"htmlhint",
				"stylelint",
				"jsonlint",
				"markdownlint",
				"flake8",
				"shellcheck",
				"yamllint",
				"sqlfluff",
				"checkstyle",
				"ktlint",
			},
		})
	end,
})

-- ********************************************************************************
-- * Snippets & Completions                                                       *
-- ********************************************************************************

-- Copilot
table.insert(plugins, {
	"zbirenbaum/copilot.lua",
	dependencies = { "zbirenbaum/copilot-cmp" },
	cmd = "Copilot",
	config = function()
		require("copilot").setup({
			suggestion = { enabled = false },
			panel = { enabled = false },
		})
		require("copilot_cmp").setup()
	end,
})

-- Snippets
table.insert(plugins, {
	"L3MON4D3/LuaSnip",
	version = "v2.*",
	dependencies = { "rafamadriz/friendly-snippets" },
	build = "make install_jsregexp",
	config = function()
		require("luasnip.loaders.from_vscode").lazy_load()
	end,
})

-- Cmp
table.insert(plugins, {
	"xzbdmw/nvim-cmp",
	branch = "dynamic",
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
		"hrsh7th/cmp-buffer",
		"hrsh7th/cmp-path",
		"hrsh7th/cmp-cmdline",
		"L3MON4D3/LuaSnip",
		"saadparwaiz1/cmp_luasnip",
		"petertriho/cmp-git",
		"zbirenbaum/copilot-cmp",
		"onsails/lspkind.nvim",
		"luckasRanarison/tailwind-tools.nvim",
	},
	event = { "InsertEnter", "CmdlineEnter" },
	config = function()
		local cmp = require("cmp")
		local lspkind = require("lspkind")
		cmp.setup({
			completion = {
				completeopt = "menu",
			},
			view = {
				entries = { name = "custom", selection_order = "near_cursor", follow_cursor = true },
			},
			sources = {
				{ name = "copilot", max_item_count = 3, group_index = 0 },
				{ name = "lazydev", max_item_count = 3, group_index = 1 },
				{ name = "nvim_lsp", max_item_count = 3, group_index = 1 },
				{ name = "luasnip", max_item_count = 3, group_index = 2 },
				{ name = "buffer", max_item_count = 3, group_index = 3 },
				{ name = "path", max_item_count = 3, group_index = 3 },
			},
			mapping = cmp.mapping.preset.insert({
				["<c-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
				["<c-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
				["<c-y>"] = cmp.mapping.confirm({ select = true }),
				["<c-space>"] = cmp.mapping.complete(),
				["<tab>"] = cmp.mapping.confirm(),
				["<c-e>"] = cmp.mapping({
					i = cmp.mapping.abort(),
					c = cmp.mapping.close(),
				}),
			}),
			snippet = {
				expand = function(args)
					require("luasnip").lsp_expand(args.body)
				end,
			},
			experimental = {
				ghost_text = true,
			},
			formatting = {
				expandable_indicator = true,
				fields = { "kind", "abbr", "menu" },
				format = lspkind.cmp_format({
					mode = "symbol",
					maxwidth = 50,
					ellipsis_char = "...",
					symbol_map = { Copilot = "" },
					before = require("tailwind-tools.cmp").lspkind_format,
				}),
			},
			window = {
				completion = cmp.config.window.bordered({
					border = "none",
					scrollbar = false,
				}),
			},
		})
		cmp.setup.filetype("gitcommit", {
			sources = {
				{ name = "cmp_git" },
				{ name = "buffer" },
			},
		})
		cmp.setup.cmdline({ "/", "?" }, {
			mapping = cmp.mapping.preset.cmdline(),
			sources = {
				{ name = "buffer" },
			},
		})
		cmp.setup.cmdline(":", {
			mapping = cmp.mapping.preset.cmdline(),
			sources = {
				{ name = "path" },
				{ name = "cmdline" },
			},
		})
	end,
})

-- ********************************************************************************
-- * Navigation                                                                   *
-- ********************************************************************************

-- Fzf lua, file finder and grepper
table.insert(plugins, {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		require("fzf-lua").setup({ "telescope" })
		vim.keymap.set("n", "<leader>ff", "<cmd>lua require('fzf-lua').files()<cr>", { desc = "Find files" })
		vim.keymap.set("n", "<leader>fg", "<cmd>lua require('fzf-lua').live_grep()<cr>", { desc = "Live grep" })
		vim.keymap.set("n", "<leader>fb", "<cmd>lua require('fzf-lua').buffers()<cr>", { desc = "Find buffers" })
	end,
})

-- Harpoon
table.insert(plugins, {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		local harpoon = require("harpoon")
		harpoon:setup()
		vim.keymap.set("n", "<leader>ha", function()
			harpoon:list():add()
		end, { desc = "Add file to Harpoon" })
		vim.keymap.set("n", "<leader>hh", function()
			harpoon.ui:toggle_quick_menu(harpoon:list())
		end, { desc = "Toggle Harpoon quick menu" })
		vim.keymap.set("n", "<c-h>", function()
			harpoon:list():select(1)
		end, { desc = "Select Harpoon mark 1" })
		vim.keymap.set("n", "<c-j>", function()
			harpoon:list():select(2)
		end, { desc = "Select Harpoon mark 2" })
		vim.keymap.set("n", "<c-k>", function()
			harpoon:list():select(3)
		end, { desc = "Select Harpoon mark 3" })
		vim.keymap.set("n", "<c-l>", function()
			harpoon:list():select(4)
		end, { desc = "Select Harpoon mark 4" })
	end,
})

-- Oil
table.insert(plugins, {
	"stevearc/oil.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local oil = require("oil")
		oil.setup({
			default_file_explorer = true,
			delete_to_trash = true,
			skip_confirm_for_simple_edits = true,
			view_options = {
				show_hidden = true,
				natural_order = true,
				is_always_hidden = function(name, _)
					return name == ".." or name == ".git"
				end,
			},
			win_options = {
				winbar = "%{v:lua.require('oil').get_current_dir()}",
			},
		})
		vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })
		if vim.fn.bufname("%") == "" and vim.bo.modifiable then
			oil.open()
		end
	end,
})

-- ********************************************************************************
-- * Quality of life                                                              *
-- ********************************************************************************

-- Copilot chat
table.insert(plugins, {
	"CopilotC-Nvim/CopilotChat.nvim",
	branch = "canary",
	dependencies = { "nvim-lua/plenary.nvim", "zbirenbaum/copilot.lua" },
	event = "VeryLazy",
	config = function()
		require("CopilotChat.integrations.cmp").setup()
		local copilotchat = require("CopilotChat")
		copilotchat.setup({
			question_header = "",
			answer_header = "",
			error_header = "",
			allow_insecure = true,
			show_help = false,
			window = {
				width = 0.4,
				title = nil,
			},
			mappings = {
				complete = {
					insert = "",
				},
			},
			prompts = {
				Explain = {
					mapping = "<leader>ae",
					description = "AI Explain",
				},
				Review = {
					mapping = "<leader>ar",
					description = "AI Review",
				},
				Tests = {
					mapping = "<leader>at",
					description = "AI Tests",
				},
				Fix = {
					mapping = "<leader>af",
					description = "AI Fix",
				},
				Optimize = {
					mapping = "<leader>ao",
					description = "AI Optimize",
				},
				FixDiagnostic = {
					mapping = "<leader>ad",
					description = "AI Diagnostic Fix",
				},
				Docs = {
					mapping = "<leader>am",
					description = "AI Documentation",
				},
				CommitStaged = {
					mapping = "<leader>ac",
					description = "AI Generate Commit",
				},
			},
		})
		vim.keymap.set({ "n", "x" }, "<leader>aa", copilotchat.toggle, { desc = "AI Toggle" })
		vim.api.nvim_create_autocmd("BufEnter", {
			pattern = "copilot-*",
			callback = function()
				vim.opt_local.relativenumber = false
				vim.opt_local.number = false
				vim.keymap.set(
					"n",
					"<c-s>",
					"<cmd>CopilotChatStop<cr>",
					{ buffer = true, desc = "CopilotChat - Stop output" }
				)
			end,
		})
	end,
})

-- Which key
table.insert(plugins, {
	"folke/which-key.nvim",
	event = "VeryLazy",
	config = function()
		require("which-key").setup()
	end,
})

-- Auto remove search highlight
table.insert(plugins, {
	"nvimdev/hlsearch.nvim",
	evnt = "BufRead",
	config = function()
		require("hlsearch").setup()
	end,
})

-- Add surround keybinds
table.insert(plugins, {
	"echasnovski/mini.surround",
	version = false,
	config = function()
		require("mini.surround").setup()
	end,
})

-- ********************************************************************************
-- * Git                                                                          *
-- ********************************************************************************

-- Gitsigns
table.insert(plugins, {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local gitsigns = require("gitsigns")
		gitsigns.setup({
			signs = {
				add = { text = "│" },
				change = { text = "│" },
				delete = { text = "˽" },
				topdelete = { text = "˹" },
				changedelete = { text = "˺" },
				untracked = { text = "┆" },
			},
			on_attach = function(bufnr)
				local opts = { buffer = bufnr }
				vim.keymap.set("n", "[g", gitsigns.prev_hunk, vim.tbl_extend("force", opts, { desc = "Previous hunk" }))
				vim.keymap.set("n", "]g", gitsigns.next_hunk, vim.tbl_extend("force", opts, { desc = "Next hunk" }))
				vim.keymap.set(
					"n",
					"<leader>gr",
					gitsigns.reset_hunk,
					vim.tbl_extend("force", opts, { desc = "Reset hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gs",
					gitsigns.stage_hunk,
					vim.tbl_extend("force", opts, { desc = "Stage hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gS",
					gitsigns.stage_buffer,
					vim.tbl_extend("force", opts, { desc = "Stage buffer" })
				)
				vim.keymap.set(
					"n",
					"<leader>gu",
					gitsigns.undo_stage_hunk,
					vim.tbl_extend("force", opts, { desc = "Undo stage hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gp",
					gitsigns.preview_hunk,
					vim.tbl_extend("force", opts, { desc = "Preview hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gb",
					gitsigns.toggle_current_line_blame,
					vim.tbl_extend("force", opts, { desc = "Toggle current line blame" })
				)
				vim.keymap.set(
					"n",
					"<leader>gd",
					gitsigns.diffthis,
					vim.tbl_extend("force", opts, { desc = "Diff this" })
				)
				vim.keymap.set("n", "<leader>gD", function()
					gitsigns.diffthis("~")
				end, vim.tbl_extend("force", opts, { desc = "Diff this (cached)" }))
				vim.keymap.set(
					"n",
					"<leader>gt",
					gitsigns.toggle_deleted,
					vim.tbl_extend("force", opts, { desc = "Toggle deleted" })
				)
				vim.keymap.set(
					{ "o", "x" },
					"ih",
					":<c-U>Gitsigns select_hunk<cr>",
					vim.tbl_extend("force", opts, { desc = "Select hunk" })
				)
			end,
		})
	end,
})

-- Add devicons
table.insert(plugins, {
	"nvim-tree/nvim-web-devicons",
	config = function()
		require("nvim-web-devicons").setup()
	end,
})

-- Lualine
table.insert(plugins, {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		require("lualine").setup({
			options = {
				theme = "catppuccin-mocha",
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				lualine_x = {
					{
						require("noice").api.statusline.mode.get,
						cond = require("noice").api.statusline.mode.has,
						color = { fg = "#ff9e64" },
					},
				},
			},
		})
	end,
})

-- Indent lines
table.insert(plugins, {
	"lukas-reineke/indent-blankline.nvim",
	main = "ibl",
	config = function()
		require("ibl").setup()
	end,
})

-- Cmdline UI
table.insert(plugins, {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
	},
	config = function()
		require("noice").setup({
			views = {
				cmdline_popup = {
					position = {
						row = vim.o.lines - 2,
						col = 0,
					},
					size = {
						width = vim.o.columns - 4,
						height = 1,
					},
					border = {
						style = "none",
					},
				},
			},
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			presets = {
				command_palette = true,
				long_message_to_split = true,
				inc_rename = false,
				lsp_doc_border = false,
			},
		})
	end,
})

-- Colorizer
table.insert(plugins, {
	"echasnovski/mini.hipatterns",
	version = false,
	config = function()
		require("mini.hipatterns").setup()
	end,
})

-- Load the lazy plugin manager and setup with the plugins table
require("lazy").setup(plugins, lazy_config)
