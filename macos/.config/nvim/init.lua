-- Vim options
require("config.options")

-- Key mappings
require("config.keymaps").default()

-- Auto commands
require("config.autocmds")

-- ********************************************************************************
-- * Package manager                                                              *
-- ********************************************************************************

-- Clone the Lazy plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Lazy configuration
local lazy_config = {
	install = { colorscheme = { "catppuccin-mocha" } },
	checker = { enabled = true },
	ui = {
		size = { width = 0.85, height = 0.85 },
		border = "rounded",
		wrap = false,
		backdrop = 100,
		icons = {
			lazy = "",
		},
	},
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip",
				"netrwPlugin",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
			},
		},
	},
}

-- Setup plugins table
local plugins = {}

-- ********************************************************************************
-- * Colorscheme                                                                  *
-- ********************************************************************************

-- Set colorscheme
table.insert(plugins, {
	"catppuccin/nvim",
	name = "catppuccin",
	priority = 1000,
	opts = {
		flavor = "mocha",
		default_integrations = false,
		term_colors = true,
		integrations = {
			treesitter = true,
			treesitter_context = true,
			harpoon = true,
			mini = true,
			cmp = true,
			which_key = true,
			gitsigns = true,
			indent_blankline = {
				enabled = true,
			},
			mason = true,
			neotest = true,
			lsp_trouble = true,
			native_lsp = {
				enabled = true,
				virtual_text = {
					errors = { "italic" },
					hints = { "italic" },
					warnings = { "italic" },
					information = { "italic" },
				},
				underlines = {
					errors = { "undercurl" },
					hints = { "undercurl" },
					warnings = { "undercurl" },
					information = { "undercurl" },
				},
				inlay_hints = {
					background = true,
				},
			},
		},
	},
	config = function(_, opts)
		require("catppuccin").setup(opts)
		vim.cmd.colorscheme("catppuccin-mocha")
	end,
})

-- ********************************************************************************
-- * Treesitter                                                                   *
-- ********************************************************************************

-- Keymaps for treesitter
table.insert(plugins, {
	"folke/which-key.nvim",
	opts = {
		spec = {
			{ "<BS>", desc = "Decrement Selection", mode = "x" },
			{ "<c-space>", desc = "Increment Selection", mode = { "x", "n" } },
		},
	},
})

-- Treesitter
table.insert(plugins, {
	"nvim-treesitter/nvim-treesitter",
	version = false,
	build = ":TSUpdate",
	event = { "BufReadPre", "BufNewFile" },
	lazy = vim.fn.argc(-1) == 0,
	init = function(plugin)
		require("lazy.core.loader").add_to_rtp(plugin)
		require("nvim-treesitter.query_predicates")
	end,
	cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
	keys = {
		{ "<c-space>", desc = "Increment Selection" },
		{ "<bs>", desc = "Decrement Selection", mode = "x" },
	},
	opts_extend = { "ensure_installed" },
	opts = {
		highlight = { enable = true },
		indent = { enable = true },
		ensure_installed = {
			"bash",
			"c",
			"diff",
			"html",
			"javascript",
			"jsdoc",
			"json",
			"jsonc",
			"lua",
			"luadoc",
			"luap",
			"markdown",
			"markdown_inline",
			"printf",
			"python",
			"query",
			"regex",
			"toml",
			"tsx",
			"typescript",
			"vim",
			"vimdoc",
			"xml",
			"yaml",
		},
		incremental_selection = {
			enable = true,
			keymaps = {
				init_selection = "<C-space>",
				node_incremental = "<C-space>",
				scope_incremental = false,
				node_decremental = "<bs>",
			},
		},
		textobjects = {
			move = {
				enable = true,
				goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
				goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
				goto_previous_start = {
					["[f"] = "@function.outer",
					["[c"] = "@class.outer",
					["[a"] = "@parameter.inner",
				},
				goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
			},
		},
	},
	config = function(_, opts)
		require("nvim-treesitter.configs").setup(opts)
	end,
})

-- Text objects for treesitter
table.insert(plugins, {
	"nvim-treesitter/nvim-treesitter-textobjects",
	event = "VeryLazy",
	enabled = true,
	config = function()
		if require("lazy.core.config").plugins["nvim-treesitter"]._.loaded then
			local plugin = require("lazy.core.config").spec.plugins["nvim-treesitter"]
			local opts = require("lazy.core.plugin").values(plugin, "opts", false)
			require("nvim-treesitter.configs").setup({ textobjects = opts.textobjects })
		end
		local move = require("nvim-treesitter.textobjects.move")
		local configs = require("nvim-treesitter.configs")
		for name, fn in pairs(move) do
			if name:find("goto") == 1 then
				move[name] = function(q, ...)
					if vim.wo.diff then
						local config = configs.get_module("textobjects.move")[name]
						for key, query in pairs(config or {}) do
							if q == query and key:find("[%]%[][cC]") then
								vim.cmd("normal! " .. key)
								return
							end
						end
					end
					return fn(q, ...)
				end
			end
		end
	end,
})

-- Automatically add closing tags for HTML and JSX
table.insert(plugins, {
	"windwp/nvim-ts-autotag",
	event = { "BufReadPre", "BufNewFile" },
	opts = {},
})

-- ********************************************************************************
-- * Language Servers                                                             *
-- ********************************************************************************

-- Lspconfig
table.insert(plugins, {
	"neovim/nvim-lspconfig",
	event = "LazyFile",
	dependencies = {
		"williamboman/mason.nvim",
		{ "williamboman/mason-lspconfig.nvim", config = function() end },
	},
	opts = {
		diagnostics = {
			underline = true,
			update_in_insert = false,
			virtual_text = {
				spacing = 4,
				source = "if_many",
				prefix = "●",
			},
			severity_sort = true,
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = "",
					[vim.diagnostic.severity.WARN] = "",
					[vim.diagnostic.severity.HINT] = "",
					[vim.diagnostic.severity.INFO] = "",
				},
			},
		},
		inlay_hints = {
			enabled = true,
		},
		codelens = {
			enabled = false,
		},
		document_highlight = {
			enabled = true,
		},
		capabilities = {
			workspace = {
				fileOperations = {
					didRename = true,
					willRename = true,
				},
			},
		},
		format = {
			formatting_options = nil,
			timeout_ms = nil,
		},
		servers = {
			lua_ls = {
				settings = {
					Lua = {
						workspace = {
							checkThirdParty = false,
						},
						codeLens = {
							enable = true,
						},
						completion = {
							callSnippet = "Replace",
						},
						doc = {
							privateName = { "^_" },
						},
						hint = {
							enable = true,
							setType = false,
							paramType = true,
							paramName = "Disable",
							semicolon = "Disable",
							arrayIndex = "Disable",
						},
					},
				},
			},
		},
		setup = {},
	},
	config = function(_, opts)
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(event)
				-- lsp_keymaps(event.buf)
			end,
		})
		for severity, icon in pairs(opts.diagnostics.signs.text) do
			local name = vim.diagnostic.severity[severity]:lower():gsub("^%l", string.upper)
			name = "DiagnosticSign" .. name
			vim.fn.sign_define(name, { text = icon, texthl = name, numhl = "" })
		end
		vim.diagnostic.config({
			underline = true,
			update_in_insert = false,
			virtual_text = {
				spacing = 4,
				source = "if_many",
				prefix = "●",
			},
			severity_sort = true,
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = "",
					[vim.diagnostic.severity.WARN] = "",
					[vim.diagnostic.severity.HINT] = "",
					[vim.diagnostic.severity.INFO] = "",
				},
			},
		})

		local capabilities = require("cmp_nvim_lsp").default_capabilities()
		local default_setup = function(server)
			require("lspconfig")[server].setup({
				capabilities = capabilities,
			})
		end
		require("mason-lspconfig").setup({
			handlers = {
				default_setup,
				lua_ls = function()
					require("lspconfig").lua_ls.setup({
						capabilities = capabilities,
					})
				end,
			},
			automatic_installation = true,
			ensure_installed = {
				"lua_ls",
				"vtsls",
				"html",
				"tailwindcss",
				"pyright",
				"angularls",
				"bashls",
				"omnisharp",
				"cssls",
				"dockerls",
				"docker_compose_language_service",
				"gradle_ls",
				"jsonls",
				"jdtls",
				"kotlin_language_server",
				"ltex",
				"markdown_oxide",
				"sqlls",
				"yamlls",
			},
		})
	end,
})

-- Cmdline tools and lsp servers
table.insert(plugins, {
	"williamboman/mason.nvim",
	cmd = "Mason",
	build = ":MasonUpdate",
	opts_extend = { "ensure_installed" },
	opts = {
		ui = {
			width = 0.85,
			height = 0.85,
			border = "rounded",
			icons = {
				package_installed = "●",
				package_pending = "➜",
				package_uninstalled = "○",
			},
			keymaps = {
				uninstall_package = "x",
				toggle_help = "?",
			},
		},
		ensure_installed = {
			"stylua",
			"shfmt",
		},
	},
	config = function(_, opts)
		require("mason").setup(opts)
		local registry = require("mason-registry")
		registry:on("package:install:success", function()
			vim.defer_fn(function()
				require("lazy.core.handler.event").trigger({
					event = "FileType",
					buf = vim.api.nvim_get_current_buf(),
				})
			end, 100)
		end)
		registry.refresh(function()
			for _, tool in ipairs(opts.ensure_installed) do
				local p = registry.get_package(tool)
				if not p:is_installed() then
					p:install()
				end
			end
		end)
	end,
})

-- ********************************************************************************
-- * Coding                                                                       *
-- ********************************************************************************
-- Development config
table.insert(plugins, {
	"folke/lazydev.nvim",
	depdendencies = {
		"justinsgithub/wezterm-types",
	},
	ft = "lua",
	opts = {
		library = {
			{ path = "wezterm-types", mods = { "wezterm" } },
		},
	},
})

-- ********************************************************************************
-- * Editor                                                                       *
-- ********************************************************************************

-- Smart Splits
table.insert(plugins, {
	"mrjones2014/smart-splits.nvim",
	opts = {},
})

-- ********************************************************************************
-- * Linting & Formatting                                                         *
-- ********************************************************************************

-- Conform
table.insert(plugins, {
	"stevearc/conform.nvim",
	dependencies = { "LittleEndianRoot/mason-conform" },
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		require("conform").setup({
			format_on_save = {
				timeout_ms = 3000,
				lsp_fallback = true,
			},
			formatters_by_ft = {
				lua = { "stylua" },
				javascript = { "prettierd" },
				typescript = { "prettierd" },
				typescriptreact = { "prettierd" },
				javascriptreact = { "prettierd" },
				html = { "prettierd" },
				css = { "prettierd" },
				json = { "prettierd" },
				jsonc = { "prettierd" },
				markdown = { "prettierd" },
				python = { "black" },
				sh = { "shfmt" },
				yaml = { "prettierd" },
				toml = { "prettierd" },
				sql = { "sql-formatter" },
				java = { "google-java-format" },
				kotlin = { "ktlint" },
				zsh = { "shfmt" },
			},
		})
		vim.keymap.set({ "n", "x" }, "<leader>cf", function()
			require("conform").format({
				timeout_ms = 2000,
				lsp_fallback = true,
			})
		end, { desc = "Format file or range (in visual mode)" })
		require("mason-conform").setup({
			automatic_installation = false,
			ensure_installed = {
				"stylua",
				"prettierd",
				"black",
				"shfmt",
				"sql-formatter",
				"google-java-format",
				"ktlint",
			},
		})
	end,
})

-- Nvim Lint
table.insert(plugins, {
	"mfussenegger/nvim-lint",
	dependencies = { "rshkarin/mason-nvim-lint" },
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			lua = { "luacheck" },
			javascript = { "eslint_d" },
			typescript = { "eslint_d" },
			typescriptreact = { "eslint_d" },
			javascriptreact = { "eslint_d" },
			html = { "htmlhint" },
			css = { "stylelint" },
			json = { "jsonlint" },
			jsonc = { "jsonlint" },
			markdown = { "markdownlint" },
			python = { "flake8" },
			sh = { "shellcheck" },
			yaml = { "yamllint" },
			sql = { "sqlfluff" },
			java = { "checkstyle" },
			kotlin = { "ktlint" },
			zsh = { "shellcheck" },
		}
		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave", "TextChanged" }, {
			callback = function()
				lint.try_lint()
			end,
		})
		vim.keymap.set({ "n", "x" }, "<leader>cl", lint.try_lint, { desc = "Lint file" })
		require("mason-nvim-lint").setup({
			automatic_installation = false,
			ensure_installed = {
				"luacheck",
				"eslint_d",
				"htmlhint",
				"stylelint",
				"jsonlint",
				"markdownlint",
				"flake8",
				"shellcheck",
				"yamllint",
				"sqlfluff",
				"checkstyle",
				"ktlint",
			},
		})
	end,
})

-- ********************************************************************************
-- * Snippets & Completions                                                       *
-- ********************************************************************************

-- Copilot
table.insert(plugins, {
	"zbirenbaum/copilot.lua",
	dependencies = { "zbirenbaum/copilot-cmp" },
	cmd = "Copilot",
	config = function()
		require("copilot").setup({
			suggestion = { enabled = false },
			panel = { enabled = false },
		})
		require("copilot_cmp").setup()
	end,
})

-- Snippets
table.insert(plugins, {
	"L3MON4D3/LuaSnip",
	version = "v2.*",
	dependencies = { "rafamadriz/friendly-snippets" },
	build = "make install_jsregexp",
	config = function()
		require("luasnip.loaders.from_vscode").lazy_load()
	end,
})

-- Cmp
table.insert(plugins, {
	"xzbdmw/nvim-cmp",
	branch = "dynamic",
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
		"hrsh7th/cmp-buffer",
		"hrsh7th/cmp-path",
		"hrsh7th/cmp-cmdline",
		"L3MON4D3/LuaSnip",
		"saadparwaiz1/cmp_luasnip",
		"petertriho/cmp-git",
		"zbirenbaum/copilot-cmp",
		"onsails/lspkind.nvim",
		"luckasRanarison/tailwind-tools.nvim",
	},
	event = { "InsertEnter", "CmdlineEnter" },
	config = function()
		local cmp = require("cmp")
		local lspkind = require("lspkind")
		cmp.setup({
			completion = {
				completeopt = "menu",
			},
			view = {
				entries = { name = "custom", selection_order = "near_cursor", follow_cursor = true },
			},
			sources = {
				{ name = "copilot", max_item_count = 3, group_index = 0 },
				{ name = "lazydev", max_item_count = 3, group_index = 1 },
				{ name = "nvim_lsp", max_item_count = 3, group_index = 1 },
				{ name = "luasnip", max_item_count = 3, group_index = 2 },
				{ name = "buffer", max_item_count = 3, group_index = 3 },
				{ name = "path", max_item_count = 3, group_index = 3 },
			},
			mapping = cmp.mapping.preset.insert({
				["<c-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
				["<c-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
				["<c-y>"] = cmp.mapping.confirm({ select = true }),
				["<c-space>"] = cmp.mapping.complete(),
				["<tab>"] = cmp.mapping.confirm(),
				["<c-e>"] = cmp.mapping({
					i = cmp.mapping.abort(),
					c = cmp.mapping.close(),
				}),
			}),
			snippet = {
				expand = function(args)
					require("luasnip").lsp_expand(args.body)
				end,
			},
			experimental = {
				ghost_text = true,
			},
			formatting = {
				expandable_indicator = true,
				fields = { "kind", "abbr", "menu" },
				format = lspkind.cmp_format({
					mode = "symbol",
					maxwidth = 50,
					ellipsis_char = "...",
					symbol_map = { Copilot = "" },
					before = require("tailwind-tools.cmp").lspkind_format,
				}),
			},
			window = {
				completion = cmp.config.window.bordered({
					border = "none",
					scrollbar = false,
				}),
			},
		})
		cmp.setup.filetype("gitcommit", {
			sources = {
				{ name = "cmp_git" },
				{ name = "buffer" },
			},
		})
		cmp.setup.cmdline({ "/", "?" }, {
			mapping = cmp.mapping.preset.cmdline(),
			sources = {
				{ name = "buffer" },
			},
		})
		cmp.setup.cmdline(":", {
			mapping = cmp.mapping.preset.cmdline(),
			sources = {
				{ name = "path" },
				{ name = "cmdline" },
			},
		})
	end,
})

-- ********************************************************************************
-- * Navigation                                                                   *
-- ********************************************************************************

-- Fzf lua, file finder and grepper
table.insert(plugins, {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		require("fzf-lua").setup({ "telescope" })
		vim.keymap.set("n", "<leader>ff", "<cmd>lua require('fzf-lua').files()<cr>", { desc = "Find files" })
		vim.keymap.set("n", "<leader>fg", "<cmd>lua require('fzf-lua').live_grep()<cr>", { desc = "Live grep" })
		vim.keymap.set("n", "<leader>fb", "<cmd>lua require('fzf-lua').buffers()<cr>", { desc = "Find buffers" })
	end,
})

-- Harpoon
table.insert(plugins, {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		local harpoon = require("harpoon")
		harpoon:setup()
		vim.keymap.set("n", "<leader>ha", function()
			harpoon:list():add()
		end, { desc = "Add file to Harpoon" })
		vim.keymap.set("n", "<leader>hh", function()
			harpoon.ui:toggle_quick_menu(harpoon:list())
		end, { desc = "Toggle Harpoon quick menu" })
		vim.keymap.set("n", "<c-h>", function()
			harpoon:list():select(1)
		end, { desc = "Select Harpoon mark 1" })
		vim.keymap.set("n", "<c-j>", function()
			harpoon:list():select(2)
		end, { desc = "Select Harpoon mark 2" })
		vim.keymap.set("n", "<c-k>", function()
			harpoon:list():select(3)
		end, { desc = "Select Harpoon mark 3" })
		vim.keymap.set("n", "<c-l>", function()
			harpoon:list():select(4)
		end, { desc = "Select Harpoon mark 4" })
	end,
})

-- Oil
table.insert(plugins, {
	"stevearc/oil.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local oil = require("oil")
		oil.setup({
			default_file_explorer = true,
			delete_to_trash = true,
			skip_confirm_for_simple_edits = true,
			view_options = {
				show_hidden = true,
				natural_order = true,
				is_always_hidden = function(name, _)
					return name == ".." or name == ".git"
				end,
			},
			win_options = {
				winbar = "%{v:lua.require('oil').get_current_dir()}",
			},
		})
		vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })
		if vim.fn.bufname("%") == "" and vim.bo.modifiable then
			oil.open()
		end
	end,
})

-- ********************************************************************************
-- * Quality of life                                                              *
-- ********************************************************************************

-- Copilot chat
table.insert(plugins, {
	"CopilotC-Nvim/CopilotChat.nvim",
	branch = "canary",
	dependencies = { "nvim-lua/plenary.nvim", "zbirenbaum/copilot.lua" },
	event = "VeryLazy",
	config = function()
		require("CopilotChat.integrations.cmp").setup()
		local copilotchat = require("CopilotChat")
		copilotchat.setup({
			question_header = "",
			answer_header = "",
			error_header = "",
			allow_insecure = true,
			show_help = false,
			window = {
				width = 0.4,
				title = nil,
			},
			mappings = {
				complete = {
					insert = "",
				},
			},
			prompts = {
				Explain = {
					mapping = "<leader>ae",
					description = "AI Explain",
				},
				Review = {
					mapping = "<leader>ar",
					description = "AI Review",
				},
				Tests = {
					mapping = "<leader>at",
					description = "AI Tests",
				},
				Fix = {
					mapping = "<leader>af",
					description = "AI Fix",
				},
				Optimize = {
					mapping = "<leader>ao",
					description = "AI Optimize",
				},
				FixDiagnostic = {
					mapping = "<leader>ad",
					description = "AI Diagnostic Fix",
				},
				Docs = {
					mapping = "<leader>am",
					description = "AI Documentation",
				},
				CommitStaged = {
					mapping = "<leader>ac",
					description = "AI Generate Commit",
				},
			},
		})
		vim.keymap.set({ "n", "x" }, "<leader>aa", copilotchat.toggle, { desc = "AI Toggle" })
		vim.api.nvim_create_autocmd("BufEnter", {
			pattern = "copilot-*",
			callback = function()
				vim.opt_local.relativenumber = false
				vim.opt_local.number = false
				vim.keymap.set(
					"n",
					"<c-s>",
					"<cmd>CopilotChatStop<cr>",
					{ buffer = true, desc = "CopilotChat - Stop output" }
				)
			end,
		})
	end,
})

-- Which key
table.insert(plugins, {
	"folke/which-key.nvim",
	event = "VeryLazy",
	config = function()
		require("which-key").setup()
	end,
})

-- Auto remove search highlight
table.insert(plugins, {
	"nvimdev/hlsearch.nvim",
	evnt = "BufRead",
	config = function()
		require("hlsearch").setup()
	end,
})

-- Add surround keybinds
table.insert(plugins, {
	"echasnovski/mini.surround",
	version = false,
	config = function()
		require("mini.surround").setup()
	end,
})

-- ********************************************************************************
-- * Git                                                                          *
-- ********************************************************************************

-- Gitsigns
table.insert(plugins, {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local gitsigns = require("gitsigns")
		gitsigns.setup({
			signs = {
				add = { text = "│" },
				change = { text = "│" },
				delete = { text = "˽" },
				topdelete = { text = "˹" },
				changedelete = { text = "˺" },
				untracked = { text = "┆" },
			},
			on_attach = function(bufnr)
				local opts = { buffer = bufnr }
				vim.keymap.set("n", "[g", gitsigns.prev_hunk, vim.tbl_extend("force", opts, { desc = "Previous hunk" }))
				vim.keymap.set("n", "]g", gitsigns.next_hunk, vim.tbl_extend("force", opts, { desc = "Next hunk" }))
				vim.keymap.set(
					"n",
					"<leader>gr",
					gitsigns.reset_hunk,
					vim.tbl_extend("force", opts, { desc = "Reset hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gs",
					gitsigns.stage_hunk,
					vim.tbl_extend("force", opts, { desc = "Stage hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gS",
					gitsigns.stage_buffer,
					vim.tbl_extend("force", opts, { desc = "Stage buffer" })
				)
				vim.keymap.set(
					"n",
					"<leader>gu",
					gitsigns.undo_stage_hunk,
					vim.tbl_extend("force", opts, { desc = "Undo stage hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gp",
					gitsigns.preview_hunk,
					vim.tbl_extend("force", opts, { desc = "Preview hunk" })
				)
				vim.keymap.set(
					"n",
					"<leader>gb",
					gitsigns.toggle_current_line_blame,
					vim.tbl_extend("force", opts, { desc = "Toggle current line blame" })
				)
				vim.keymap.set(
					"n",
					"<leader>gd",
					gitsigns.diffthis,
					vim.tbl_extend("force", opts, { desc = "Diff this" })
				)
				vim.keymap.set("n", "<leader>gD", function()
					gitsigns.diffthis("~")
				end, vim.tbl_extend("force", opts, { desc = "Diff this (cached)" }))
				vim.keymap.set(
					"n",
					"<leader>gt",
					gitsigns.toggle_deleted,
					vim.tbl_extend("force", opts, { desc = "Toggle deleted" })
				)
				vim.keymap.set(
					{ "o", "x" },
					"ih",
					":<c-U>Gitsigns select_hunk<cr>",
					vim.tbl_extend("force", opts, { desc = "Select hunk" })
				)
			end,
		})
	end,
})

-- Add devicons
table.insert(plugins, {
	"nvim-tree/nvim-web-devicons",
	config = function()
		require("nvim-web-devicons").setup()
	end,
})

-- Lualine
table.insert(plugins, {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		require("lualine").setup({
			options = {
				theme = "catppuccin-mocha",
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				lualine_x = {
					{
						require("noice").api.statusline.mode.get,
						cond = require("noice").api.statusline.mode.has,
						color = { fg = "#ff9e64" },
					},
				},
			},
		})
	end,
})

-- Indent lines
table.insert(plugins, {
	"lukas-reineke/indent-blankline.nvim",
	main = "ibl",
	config = function()
		require("ibl").setup()
	end,
})

-- Cmdline UI
table.insert(plugins, {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
	},
	config = function()
		require("noice").setup({
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
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			presets = {
				command_palette = true,
				long_message_to_split = true,
				inc_rename = false,
				lsp_doc_border = false,
			},
		})
	end,
})

-- Colorizer
table.insert(plugins, {
	"echasnovski/mini.hipatterns",
	version = false,
	config = function()
		require("mini.hipatterns").setup()
	end,
})

-- Load the lazy plugin manager and setup with the plugins table
require("lazy").setup(plugins, lazy_config)
