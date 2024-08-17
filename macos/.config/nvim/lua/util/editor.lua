local M = {}

function M.dial(increment, g)
	local mode = vim.fn.mode(true)
	-- Use visual commands for VISUAL 'v', VISUAL LINE 'V' and VISUAL BLOCK '\22'
	local is_visual = mode == "v" or mode == "V" or mode == "\22"
	local func = (increment and "inc" or "dec") .. (g and "_g" or "_") .. (is_visual and "visual" or "normal")
	return require("dial.map")[func]()
end

return M
