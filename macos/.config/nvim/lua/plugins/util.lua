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
}
