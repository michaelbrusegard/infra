return {
	{
		"mfussenegger/nvim-lint",
		dependencies = { "mason.nvim" },
		event = "LazyFile",
		opts = {
			linters_by_ft = {
				dockerfile = { "hadolint" },
				kotlin = { "ktlint" },
				markdown = { "markdownlint-cli2" },
			},
			linters = {},
		},
		keys = { { "<leader>cl", mode = { "n", "x" }, "<cmd>lua require('util.lint').lint()<cr>", desc = "Code Lint" } },
		config = function(_, opts)
			local lint = require("lint")
			for name, linter in pairs(opts.linters) do
				if type(linter) == "table" and type(lint.linters[name]) == "table" then
					lint.linters[name] = vim.tbl_deep_extend("force", lint.linters[name], linter)
					if type(linter.prepend_args) == "table" then
						lint.linters[name].args = lint.linters[name].args or {}
						vim.list_extend(lint.linters[name].args, linter.prepend_args)
					end
				else
					lint.linters[name] = linter
				end
			end
			lint.linters_by_ft = opts.linters_by_ft

			vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
				group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
				callback = require("util.lint").debounce(100, require("util.lint").lint),
			})
		end,
	},
}
