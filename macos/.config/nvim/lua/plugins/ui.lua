return {
	-- Statusline
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		init = function()
			vim.g.lualine_laststatus = vim.o.laststatus
			if vim.fn.argc(-1) > 0 then
				-- Set an empty statusline till lualine loads
				vim.o.statusline = " "
			else
				-- hide the statusline on the starter page
				vim.o.laststatus = 0
			end
		end,
		opts = function()
			-- PERF: we don't need this lualine require madness 🤷
			local lualine_require = require("lualine_require")
			lualine_require.require = require

			vim.o.laststatus = vim.g.lualine_laststatus

			local opts = {
				options = {
					theme = "auto",
					globalstatus = vim.o.laststatus == 3,
					component_separators = { left = "", right = "" },
					section_separators = { left = "", right = "" },
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = {
						"branch",
						"diff",
						{
							"diagnostics",
							symbols = { error = " ", warn = " ", info = " ", hint = " " },
						},
					},
					lualine_c = {
						require("util.ui").root_dir(),
						{ "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
						require("util.ui").pretty_path(),
					},
					lualine_x = {},
				},
				extensions = { "lazy", "mason", "oil", "trouble", "nvim-dap-ui" },
			}
			return opts
		end,
	},
	-- Indent guides for Neovim
	{
		"lukas-reineke/indent-blankline.nvim",
		event = "LazyFile",
		opts = {
			indent = {
				char = "▏",
				tab_char = "▏",
			},
			exclude = {
				filetypes = {
					"help",
					"Trouble",
					"trouble",
					"lazy",
					"mason",
					"lazyterm",
				},
			},
		},
		main = "ibl",
	},
	-- Highly experimental plugin that completely replaces the UI for messages, cmdline and the popupmenu.
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			routes = {
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "%d+L, %d+B" },
							{ find = "; after #%d+" },
							{ find = "; before #%d+" },
						},
					},
					view = "mini",
				},
			},
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
			presets = {
				command_palette = true,
				long_message_to_split = true,
				inc_rename = false,
				lsp_doc_border = false,
			},
		},
		keys = {
			{
				"<s-enter>",
				"<cmd>lua require('noice').redirect(vim.fn.getcmdline())<cr>",
				mode = "c",
				desc = "Redirect Cmdline",
			},
			{ "<leader>lp", "<cmd>lua require('noice').cmd('last')<cr>", desc = "Log Prev Message" },
			{ "<leader>lh", "<cmd>lua require('noice').cmd('history')<cr>", desc = "Log History" },
			{
				"<c-f>",
				function()
					if not require("noice.lsp").scroll(4) then
						return "<c-f>"
					end
				end,
				silent = true,
				expr = true,
				desc = "Scroll Forward",
				mode = { "i", "n", "s" },
			},
			{
				"<c-b>",
				function()
					if not require("noice.lsp").scroll(-4) then
						return "<c-b>"
					end
				end,
				silent = true,
				expr = true,
				desc = "Scroll Backward",
				mode = { "i", "n", "s" },
			},
		},
		config = function(_, opts)
			-- HACK: noice shows messages from before it was enabled,
			-- but this is not ideal when Lazy is installing plugins,
			-- so clear the messages in this case.
			if vim.o.filetype == "lazy" then
				vim.cmd([[messages clear]])
			end
			require("noice").setup(opts)
		end,
	},
	-- Ui components
	{ "MunifTanjim/nui.nvim", lazy = true },
}
