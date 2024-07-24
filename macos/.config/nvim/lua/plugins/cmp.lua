return {
	-- Auto completion
	-- "xzbdmw/nvim-cmp",
	-- branch = "dynamic",
	{
		"hrsh7th/nvim-cmp",
		version = false,
		event = "InsertEnter",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
		},
		opts = function()
			vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
			local cmp = require("cmp")
			local defaults = require("cmp.config.default")()
			local auto_select = true
			return {
				auto_brackets = {},
				completion = {
					completeopt = "menu,menuone,noinsert" .. (auto_select and "" or ",noselect"),
				},
				preselect = auto_select and cmp.PreselectMode.Item or cmp.PreselectMode.None,
				mapping = cmp.mapping.preset.insert({
					["<c-b>"] = cmp.mapping.scroll_docs(-4),
					["<c-f>"] = cmp.mapping.scroll_docs(4),
					["<c-space>"] = cmp.mapping.complete(),
					["<cr>"] = require("util.cmp").confirm({ select = auto_select }),
					["<c-y>"] = require("util.cmp").confirm({ select = true }),
					["<s-cr>"] = require("util.cmp").confirm({ behavior = cmp.ConfirmBehavior.Replace }),
					["<c-cr>"] = function(fallback)
						cmp.abort()
						fallback()
					end,
				}),
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "path" },
				}, {
					{ name = "buffer" },
				}),
				formatting = {
					format = function(_, item)
						local icons = {
							Array = "",
							Boolean = "󰨙",
							Class = "",
							Codeium = "󰘦",
							Color = "",
							Control = "",
							Collapsed = "",
							Constant = "󰏿",
							Constructor = "",
							Copilot = "",
							Enum = "",
							EnumMember = "",
							Event = "",
							Field = "",
							File = "",
							Folder = "",
							Function = "󰊕",
							Interface = "",
							Key = "",
							Keyword = "",
							Method = "󰊕",
							Module = "",
							Namespace = "󰦮",
							Null = "",
							Number = "󰎠",
							Object = "",
							Operator = "",
							Package = "",
							Property = "",
							Reference = "",
							Snippet = "",
							String = "",
							Struct = "󰆼",
							TabNine = "󰏚",
							Text = "",
							TypeParameter = "",
							Unit = "",
							Value = "",
							Variable = "󰀫",
						}
						if icons[item.kind] then
							item.kind = icons[item.kind] .. item.kind
						end

						local widths = {
							abbr = 40,
							menu = 30,
						}

						for key, width in pairs(widths) do
							if item[key] and vim.fn.strdisplaywidth(item[key]) > width then
								item[key] = vim.fn.strcharpart(item[key], 0, width - 1) .. "…"
							end
						end

						return item
					end,
				},
				window = {
					completion = cmp.config.window.bordered({
						border = "none",
						scrollbar = false,
					}),
				},
				experimental = {
					ghost_text = {
						hl_group = "CmpGhostText",
					},
				},
				sorting = defaults.sorting,
			}
		end,
		main = "util.cmp",
	},
	-- Snippets
	{
		"nvim-cmp",
		dependencies = {
			{
				"garymjr/nvim-snippets",
				opts = {
					friendly_snippets = true,
				},
				dependencies = { "rafamadriz/friendly-snippets" },
			},
		},
		opts = function(_, opts)
			opts.snippet = {
				expand = function(item)
					return require("util.cmp").expand(item.body)
				end,
			}
			table.insert(opts.sources, { name = "snippets" })
		end,
		keys = {
			{
				"<Tab>",
				function()
					return vim.snippet.active({ direction = 1 }) and "<cmd>lua vim.snippet.jump(1)<cr>" or "<Tab>"
				end,
				expr = true,
				silent = true,
				mode = { "i", "s" },
			},
			{
				"<S-Tab>",
				function()
					return vim.snippet.active({ direction = -1 }) and "<cmd>lua vim.snippet.jump(-1)<cr>" or "<S-Tab>"
				end,
				expr = true,
				silent = true,
				mode = { "i", "s" },
			},
		},
	},
	-- Comments
	{
		"folke/ts-comments.nvim",
		event = "VeryLazy",
		opts = {},
	},
  -- Better config dev behavior
	{
		"folke/lazydev.nvim",
		depdendencies = {
			"justinsgithub/wezterm-types",
		},
		ft = "lua",
		cmd = "LazyDev",
		opts = {
			library = {
				"lazy.nvim",
				{ path = "luvit-meta/library", words = { "vim%.uv" } },
				{ path = "wezterm-types", mods = { "wezterm" } },
			},
		},
	},
	{ "Bilal2453/luvit-meta", lazy = true },
	{
		"hrsh7th/nvim-cmp",
		opts = function(_, opts)
			table.insert(opts.sources, { name = "lazydev", group_index = 0 })
		end,
	},
}
