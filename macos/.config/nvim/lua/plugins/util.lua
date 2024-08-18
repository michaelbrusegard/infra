return {
	-- Library used by other plugins
	{ "nvim-lua/plenary.nvim", lazy = true },
	-- Show colors in the code
	{
		"echasnovski/mini.hipatterns",
		event = "LazyFile",
		opts = {},
	},
	-- Learn the best way to do vim commands
	{
		"m4xshen/hardtime.nvim",
		event = "LazyFile",
		dependencies = { "MunifTanjim/nui.nvim", "nvim-lua/plenary.nvim" },
		opts = {},
	},
	-- Screenshots
	{
		"michaelrommel/nvim-silicon",
		lazy = true,
		cmd = "Silicon",
		main = "nvim-silicon",
		keys = {
			{
				"<leader>ss",
				mode = { "n", "x" },
				"<cmd>lua require('nvim-silicon').clip()<cr>",
				desc = "Take Screenshot",
			},
		},
		opts = {
			disable_defaults = true,
			language = function()
				return vim.bo.filetype
			end,
			window_title = function()
				return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), ":t")
			end,
			to_clipboard = true,
			gobble = true,
			num_separator = " ",
		},
	},
	-- Markdown
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = function()
			vim.fn["mkdp#util#install"]()
		end,
		keys = {
			{
				"<leader>cp",
				ft = "markdown",
				"<cmd>MarkdownPreviewToggle<cr>",
				desc = "Markdown Preview",
			},
		},
		config = function()
			vim.cmd([[do FileType]])
		end,
	},
}
