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
			{
				"<leader>cF",
				"<cmd>ConformInfo<cr>",
				desc = "Formatter Info",
			},
		},
		opts = {
			notify_on_error = true,
			notify_no_formatters = true,
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
				css = { "prettierd", "biome" },
				graphql = { "prettierd", "biome" },
				handlebars = { "prettierd", "biome" },
				html = { "prettierd", "biome" },
				javascript = { "prettierd", "biome" },
				javascriptreact = { "prettierd", "biome" },
				json = { "prettierd", "biome" },
				jsonc = { "prettierd", "biome" },
				less = { "prettierd", "biome" },
				markdown = { "prettierd", "biome", "markdownlint-cli2", "markdown-toc" },
				["markdown.mdx"] = { "prettierd", "biome", "markdownlint-cli2", "markdown-toc" },
				scss = { "prettierd", "biome" },
				typescript = { "prettierd", "biome" },
				typescriptreact = { "prettierd", "biome" },
				vue = { "prettierd", "biome" },
				yaml = { "prettierd", "biome" },
				kotlin = { "ktlint" },
				cs = { "csharpier" },
				rust = { lsp_format = "prefer" },
			},
			-- The options you set here will be merged with the builtin formatters.
			-- You can also define any custom formatters here.
			formatters = {
				injected = { options = { ignore_errors = true } },
				prettierd = {
					condition = function(_, ctx)
						local filetype = vim.api.nvim_buf_get_option(ctx.buf, "filetype")
						if filetype == "markdown" or filetype == "markdown.mdx" then
							return true
						end
						return require("util.format").find_config(ctx.filename, {
							".prettierrc",
							".prettierrc.json",
							".prettierrc.yml",
							".prettierrc.yaml",
							".prettierrc.json5",
							".prettierrc.js",
							".prettierrc.cjs",
							".prettierrc.toml",
							"prettier.config.js",
							"prettier.config.cjs",
						})
					end,
				},
				biome = {
					condition = function(_, ctx)
						return require("util.format").find_config(ctx.filename, { "biome.json", "biome.jsonc" })
					end,
				},
				["markdown-toc"] = {
					condition = function(_, ctx)
						for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
							if line:find("<!%-%- toc %-%->") then
								return true
							end
						end
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
