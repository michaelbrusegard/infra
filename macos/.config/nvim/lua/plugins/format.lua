return {
	{
		"stevearc/conform.nvim",
		dependencies = { "mason.nvim" },
		event = "LazyFile",
		cmd = "ConformInfo",
		keys = {
			{
				"<leader>cf",
				mode = { "n", "x" },
				"<cmd>lua require('conform').format({ formatters = { 'injected' }, timeout_ms = 3000 })<cr>",
				desc = "Format",
			},
		},
		opts = {
			default_format_opts = {
				timeout_ms = 3000,
				async = false,
				quiet = false,
				lsp_format = "fallback",
			},
			format_on_save = {
				timeout_ms = 3000,
				lsp_format = "fallback",
			},
			formatters_by_ft = {
				lua = { "stylua" },
				sh = { "shfmt" },
			},
			-- The options you set here will be merged with the builtin formatters.
			-- You can also define any custom formatters here.
			formatters = {
				injected = { options = { ignore_errors = true } },
				-- # Example of using dprint only when a dprint.json file is present
				-- dprint = {
				--   condition = function(ctx)
				--     return vim.fs.find({ "dprint.json" }, { path = ctx.filename, upward = true })[1]
				--   end,
				-- },
				--
				-- # Example of using shfmt with extra args
				-- shfmt = {
				--   prepend_args = { "-i", "2", "-ci" },
				-- },
			},
		},
	},
}
