local M = {}

function M.find_config(filename, config_files)
	return vim.fs.find(config_files, {
		upward = true,
		stop = vim.fs.dirname(filename),
		path = vim.fs.dirname(filename),
	})[1]
end

return M
