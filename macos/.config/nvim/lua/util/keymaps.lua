local M = {}

-- Function to escape special characters for search
function M.escape_term(term)
	return vim.fn.escape(term, "/\\")
end

-- Function to remove buffer without closing window
function M.bufremove(buf)
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
function M.delmarks()
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

-- Open Lazy
function M.open_lazy()
	if not vim.g.float_open then
		vim.g.float_open = true
		vim.cmd("Lazy")
	end
end

-- Open Mason
function M.open_mason()
	if not vim.g.float_open then
		vim.g.float_open = true
		vim.cmd("Mason")
	end
end

-- Git in floating window
function M.open_git(args)
	if vim.g.float_open then
		return
	end
	vim.g.float_open = true
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
	local command = table.concat({ "lazygit", args }, " ")
	vim.fn.termopen(command, {
		on_exit = function()
			vim.api.nvim_win_close(win, true)
		end,
	})
	vim.bo.filetype = "git"
	vim.cmd("startinsert")
end

function M.open_git_file_commits()
	local file = vim.api.nvim_buf_get_name(0)
	local args = { "lazygit", "-f", vim.trim(file) }
	M.open_git(args)
end

-- Get git command for line blaming
function M.open_git_blame()
	if vim.g.float_open then
		return
	end
	vim.g.float_open = true
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
	require("lazy.util").float_cmd(command, {
		filetype = "git",
		size = {
			width = 0.85,
			height = 0.85,
		},
		border = "rounded",
	})
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
				M.maximize()
			end,
		})
		is_maximized = true
	end
end

-- Toggle signs in sign column
function M.toggle_signs()
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

return M
