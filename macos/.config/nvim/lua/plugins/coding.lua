return {
	-- Auto completion
	{
		-- "hrsh7th/nvim-cmp",
		"xzbdmw/nvim-cmp",
		branch = "dynamic",
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
			return {
				auto_brackets = {},
				completion = {
					completeopt = "menu,menuone,noinsert",
				},
				preselect = cmp.PreselectMode.Item or cmp.PreselectMode.None,
				mapping = cmp.mapping.preset.insert({
					["<c-b>"] = cmp.mapping.scroll_docs(-4),
					["<c-f>"] = cmp.mapping.scroll_docs(4),
					["<c-space>"] = cmp.mapping.complete(),
					["<cr>"] = require("util.coding").confirm({ select = true }),
					["<c-y>"] = require("util.coding").confirm({ select = true }),
					["<s-cr>"] = require("util.coding").confirm({ behavior = cmp.ConfirmBehavior.Replace }),
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
							Array = " ",
							Boolean = "󰨙 ",
							Class = " ",
							Codeium = "󰘦 ",
							Color = " ",
							Control = " ",
							Collapsed = " ",
							Constant = "󰏿 ",
							Constructor = " ",
							Copilot = " ",
							Enum = " ",
							EnumMember = " ",
							Event = " ",
							Field = " ",
							File = " ",
							Folder = " ",
							Function = "󰊕 ",
							Interface = " ",
							Key = " ",
							Keyword = " ",
							Method = "󰊕 ",
							Module = " ",
							Namespace = "󰦮 ",
							Null = " ",
							Number = "󰎠 ",
							Object = " ",
							Operator = " ",
							Package = " ",
							Property = " ",
							Reference = " ",
							Snippet = " ",
							String = " ",
							Struct = "󰆼 ",
							TabNine = "󰏚 ",
							Text = " ",
							TypeParameter = " ",
							Unit = " ",
							Value = " ",
							Variable = "󰀫 ",
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
		config = function(_, opts)
			require("util.coding").setup(opts)
		end,
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
					return require("util.coding").expand(item.body)
				end,
			}
			table.insert(opts.sources, { name = "snippets" })
		end,
		keys = {
			{
				"<tab>",
				function()
					return vim.snippet.active({ direction = 1 }) and "<cmd>lua vim.snippet.jump(1)<cr>" or "<tab>"
				end,
				expr = true,
				silent = true,
				mode = { "i", "s" },
			},
			{
				"<s-tab>",
				function()
					return vim.snippet.active({ direction = -1 }) and "<cmd>lua vim.snippet.jump(-1)<cr>" or "<s-tab>"
				end,
				expr = true,
				silent = true,
				mode = { "i", "s" },
			},
		},
	},
	-- Commandline completions
	{
		"hrsh7th/cmp-cmdline",
		config = function()
			local cmp = require("cmp")
			cmp.setup.cmdline(":", {
				sources = cmp.config.sources({
					{ name = "path" },
				}, {
					{
						name = "cmdline",
						option = {
							ignore_cmds = { "Man", "!" },
						},
					},
				}),
			})
		end,
	},
	-- Auto pairs
	{
		"echasnovski/mini.pairs",
		event = "VeryLazy",
		opts = {
			modes = { insert = true, command = true, terminal = false },
			skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
			skip_ts = { "string" },
			skip_unbalanced = true,
			markdown = true,
		},
		config = function(_, opts)
			require("util.coding").pairs(opts)
		end,
	},
	-- Add surround keymaps
	{
		"echasnovski/mini.surround",
		event = "VeryLazy",
		version = false,
		keys = function(_, keys)
			-- Populate the keys based on the user's options
			local opts = require("util.lazy").opts("mini.surround")
			local mappings = {
				{ opts.mappings.add, desc = "Add Surrounding", mode = { "n", "v" } },
				{ opts.mappings.delete, desc = "Delete Surrounding" },
				{ opts.mappings.find, desc = "Find Right Surrounding" },
				{ opts.mappings.find_left, desc = "Find Left Surrounding" },
				{ opts.mappings.highlight, desc = "Highlight Surrounding" },
				{ opts.mappings.replace, desc = "Replace Surrounding" },
				{ opts.mappings.update_n_lines, desc = "Update `MiniSurround.config.n_lines`" },
			}
			mappings = vim.tbl_filter(function(m)
				return m[1] and #m[1] > 0
			end, mappings)
			return vim.list_extend(mappings, keys)
		end,
		opts = {
			mappings = {
				add = "gsa",
				delete = "gsd",
				find = "gsf",
				find_left = "gsF",
				highlight = "gsh",
				replace = "gsr",
				update_n_lines = "gsn",
			},
		},
	},
	-- Better text-objects
	{
		"echasnovski/mini.ai",
		event = "VeryLazy",
		opts = function()
			local ai = require("mini.ai")
			return {
				n_lines = 500,
				custom_textobjects = {
					o = ai.gen_spec.treesitter({
						a = { "@block.outer", "@conditional.outer", "@loop.outer" },
						i = { "@block.inner", "@conditional.inner", "@loop.inner" },
					}),
					f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
					c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
					t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
					d = { "%f[%d]%d+" },
					e = {
						{
							"%u[%l%d]+%f[^%l%d]",
							"%f[%S][%l%d]+%f[^%l%d]",
							"%f[%P][%l%d]+%f[^%l%d]",
							"^[%l%d]+%f[^%l%d]",
						},
						"^().*()$",
					},
					i = require("util.coding").ai_indent,
					g = require("util.coding").ai_buffer,
					u = ai.gen_spec.function_call(),
					U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
				},
			}
		end,
		config = function(_, opts)
			require("mini.ai").setup(opts)
			require("util.lazy").on_load("which-key.nvim", function()
				vim.schedule(function()
					require("util.coding").ai_whichkey(opts)
				end)
			end)
		end,
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
				{ path = "luvit-meta/library", words = { "vim%.uv" } },
				{ path = "wezterm-types", mods = { "wezterm" } },
			},
		},
	},
	{ "Bilal2453/luvit-meta", lazy = true },
	{
		"nvim-cmp",
		opts = function(_, opts)
			table.insert(opts.sources, { name = "lazydev", group_index = 0 })
		end,
	},
	-- Copilot
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		build = ":Copilot auth",
		opts = {
			suggestion = { enabled = false },
			panel = { enabled = false },
			filetypes = {
				markdown = true,
				help = true,
			},
		},
	},
	-- Copilot cmp source
	{
		"nvim-cmp",
		dependencies = {
			{
				"zbirenbaum/copilot-cmp",
				dependencies = "copilot.lua",
				opts = {},
				config = function(_, opts)
					local copilot_cmp = require("copilot_cmp")
					copilot_cmp.setup(opts)
					-- Attach cmp source whenever copilot attaches
					-- Fixes lazy-loading issues with the copilot cmp source
					vim.api.nvim_create_autocmd("LspAttach", {
						callback = function(event)
							local client = vim.lsp.get_client_by_id(event.data.client_id)
							if client and client.name == "copilot" then
								copilot_cmp._on_insert_enter({})
							end
						end,
					})
				end,
			},
		},
		opts = function(_, opts)
			table.insert(opts.sources, 1, {
				name = "copilot",
				group_index = 1,
				priority = 100,
			})
		end,
	},
	-- Copilot chat
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		branch = "canary",
		cmd = "CopilotChat",
		opts = function()
			local select = require("CopilotChat.select")
			return {
				model = "gpt-4",
				auto_insert_mode = true,
				auto_follow_cursor = false,
				show_help = false,
				question_header = "",
				answer_header = "",
				window = {
					width = 0.4,
				},
				mappings = {
					complete = {
						insert = "",
					},
				},
				selection = function(source)
					return select.visual(source)
				end,
				prompts = {
					Review = {
						prompt = "/COPILOT_REVIEW Review the selected code.",
						callback = function(response, source)
							local ns = vim.api.nvim_create_namespace("copilot_review")
							local diagnostics = {}
							for line in response:gmatch("[^\r\n]+") do
								if line:find("^line=") then
									local start_line = nil
									local end_line = nil
									local message = nil
									local single_match, message_match = line:match("^line=(%d+): (.*)$")
									if not single_match then
										local start_match, end_match, m_message_match =
											line:match("^line=(%d+)-(%d+): (.*)$")
										if start_match and end_match then
											start_line = tonumber(start_match)
											end_line = tonumber(end_match)
											message = m_message_match
										end
									else
										start_line = tonumber(single_match)
										end_line = start_line
										message = message_match
									end

									if start_line and end_line then
										table.insert(diagnostics, {
											lnum = start_line - 1,
											end_lnum = end_line - 1,
											col = 0,
											message = message,
											severity = vim.diagnostic.severity.WARN,
											source = "Copilot Review",
										})
									end
								end
							end
							vim.diagnostic.set(ns, source.bufnr, diagnostics)
						end,
					},
					Explain = {
						prompt = "/COPILOT_EXPLAIN Write an explanation for the active selection as paragraphs of text.",
					},
					Optimize = {
						prompt = "/COPILOT_GENERATE Optimize the selected code to improve performance and readablilty.",
					},
					Tests = {
						prompt = "/COPILOT_GENERATE Please generate tests for my code.",
					},
					FixDiagnostic = {
						prompt = "Please assist with the following diagnostic issue in file:",
						selection = select.diagnostics,
					},
					Heading = {
						prompt = "Please provide a single-line comment heading for the selected code. Only return the heading.",
					},
					BetterNamings = {
						prompt = "Please provide better names for the following variables and functions.",
					},
				},
			}
		end,
		keys = {
			{ "<c-s>", "<cr>", ft = "copilot-chat", desc = "Submit Prompt", remap = true },
			{ "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
			{
				"<leader>aa",
				function()
					return require("CopilotChat").toggle()
				end,
				desc = "Toggle",
				mode = { "n", "v" },
			},
			{ "<leader>ae", "<cmd>CopilotChatExplain<cr>", desc = "Explain code", mode = { "n", "v" } },
			{ "<leader>at", "<cmd>CopilotChatTests<cr>", desc = "Generate tests", mode = { "n", "v" } },
			{ "<leader>ar", "<cmd>CopilotChatReview<cr>", desc = "Review code", mode = { "n", "v" } },
			{ "<leader>ao", "<cmd>CopilotChatOptimize<cr>", desc = "Optimize code", mode = { "n", "v" } },
			{ "<leader>ad", "<cmd>CopilotChatFixDiagnostic<cr>", desc = "Diagnostics", mode = { "n", "v" } },
			{ "<leader>ah", "<cmd>CopilotChatHeading<cr>", desc = "Suggest Heading", mode = { "n", "v" } },
			{ "<leader>an", "<cmd>CopilotChatBetterNamings<cr>", desc = "Better Naming", mode = { "n", "v" } },
			{
				"<leader>aq",
				function()
					local input = vim.fn.input("Quick Chat: ")
					if input ~= "" then
						require("CopilotChat").ask(input)
					end
				end,
				desc = "Quick Chat",
				mode = { "n", "v" },
			},
			-- Show prompts actions with fzf
			{
				"<leader>ap",
				require("util.coding").copilot_pick("prompt"),
				desc = "Prompt Actions Ai",
				mode = { "n", "v" },
			},
		},
		config = function(_, opts)
			local chat = require("CopilotChat")
			require("CopilotChat.integrations.cmp").setup()

			vim.api.nvim_create_autocmd("BufEnter", {
				pattern = "copilot-chat",
				callback = function()
					vim.opt_local.relativenumber = false
					vim.opt_local.number = false
					vim.keymap.set("n", "<C-s>", "<cmd>CopilotChatStop<cr>", { buffer = true })
				end,
			})

			chat.setup(opts)
		end,
	},
}
