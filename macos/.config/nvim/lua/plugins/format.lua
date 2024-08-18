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
				python = { "black" },
				css = { "prettierd" },
				graphql = { "prettierd" },
				handlebars = { "prettierd" },
				html = { "prettierd" },
				javascript = { "prettierd" },
				javascriptreact = { "prettierd" },
				json = { "prettierd" },
				jsonc = { "prettierd" },
				less = { "prettierd" },
				markdown = { "prettierd", "markdownlint-cli2" },
				["markdown.mdx"] = { "prettierd", "markdownlint-cli2" },
				scss = { "prettierd" },
				typescript = { "prettierd" },
				typescriptreact = { "prettierd" },
				vue = { "prettierd" },
				yaml = { "prettierd" },
				kotlin = { "ktlint" },
				cs = { "csharpier" },
			},
			-- The options you set here will be merged with the builtin formatters.
			-- You can also define any custom formatters here.
			formatters = {
				injected = { options = { ignore_errors = true } },
				prettierd = {
					condition = function(_, ctx)
						vim.fn.system({ "prettierd", "--find-config-path", ctx.filename })
						return vim.v.shell_error == 0
					end,
				},
				["markdownlint-cli2"] = {
					condition = function(_, ctx)
						local diag = vim.tbl_filter(function(d)
							return d.source == "markdownlint"
						end, vim.diagnostic.get(ctx.buf))
						return #diag > 0
					end,
				},
				csharpier = {
					command = "dotnet-csharpier",
					args = { "--write-stdout" },
				},
			},
		},
	},
}
