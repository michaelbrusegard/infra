-- luacheck: globals vim

-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ********************************************************************************
-- * Options                                                                      *
-- ********************************************************************************

-- Make line numbers default
vim.opt.number = true

-- Add relative line numbers, to help with jumping
vim.opt.relativenumber = true

-- Set the number of spaces that a <Tab> in the file counts for
vim.opt.tabstop = 4

-- Number of spaces a <Tab> counts for while editing
vim.opt.softtabstop = 4

-- Set the number of spaces to use for each step of (auto)indent
vim.opt.shiftwidth = 4

-- Convert tabs to spaces
vim.opt.expandtab = true

-- Enable mouse mode, can be useful for resizing splits
vim.opt.mouse = "a"

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Disable line wrapping
vim.opt.wrap = false

-- Keep signcolumn on by default
vim.opt.signcolumn = "yes"

-- Decrease update time
vim.opt.updatetime = 50

-- Decrease mapped sequence wait time, displays which-key popup sooner
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Preview substitutions live, as you type!
vim.opt.inccommand = "split"

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 13

-- Same as scrolloff, but for the horizontal axis
vim.opt.sidescrolloff = 13

-- Enable highlight on search
vim.opt.hlsearch = true

-- Enables incremental search, highlights matches while typing
vim.opt.incsearch = true

-- Set the command line height to 0, to disable it when not in use
vim.opt.cmdheight = 0

-- Set the popup menu height
vim.opt.pumheight = 7

-- ********************************************************************************
-- * Keymaps                                                                      *
-- ********************************************************************************

-- Exit terminal mode in the builtin terminal with a shortcut that is easier
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Copy to clipboard using global binding
vim.keymap.set({ "n", "v" }, "<Char-0xCA>", '"+y')

-- Paste from clipboard using global binding
vim.keymap.set({ "n", "v" }, "<Char-0xCB>", '"+p')
vim.keymap.set("i", "<Char-0xCB>", function()
	return vim.api.nvim_replace_termcodes('<Esc>"+pi', true, true, true)
end, { expr = true })
vim.keymap.set("c", "<Char-0xCB>", "<C-R>+")

-- Preserves clipboard when pasting with leader
vim.keymap.set("x", "<leader>p", '"_dP', { desc = "Paste without overriding clipboard" })

-- Preserve clipboard when deleting with leader
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d', { desc = "Delete without overriding clipboard" })

-- Open diagnostics window
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open diagnostics window" })

-- Keep selection when indenting
vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")

-- Open mason
vim.api.nvim_set_keymap("n", "<leader>m", "<cmd>Mason<cr>", { desc = "Open Mason" })

-- Open lazy
vim.api.nvim_set_keymap("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Open Lazy" })

-- Save file
vim.api.nvim_set_keymap("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })

-- Quit file
vim.api.nvim_set_keymap("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit file" })

-- Save and quit file
vim.api.nvim_set_keymap("n", "<leader>x", "<cmd>x<cr>", { desc = "Save and quit file" })

-- ********************************************************************************
-- * Autocommands                                                                 *
-- ********************************************************************************

-- Highlight when yanking text
vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		vim.highlight.on_yank()
	end,
})

-- Prevent automatic comments on new lines
vim.api.nvim_create_autocmd("BufEnter", {
	pattern = "",
	command = "set fo-=c fo-=r fo-=o",
})

-- Remove trailing whitespace on save
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
	pattern = "*",
	command = ":%s/\\s\\+$//e",
})

-- Auto save on buffer leave or focus lost
vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
	command = [[if &modified && !&readonly && expand("%") != "" && &buftype == "" | silent! update | endif]],
})

-- ********************************************************************************
-- * Package manager                                                              *
-- ********************************************************************************

-- Clone the Lazy plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- Lazy configuration
local config = {
	ui = {
		icons = {
			loaded = "✓",
			start = "➜",
			not_loaded = "✗",
		},
	},
}

-- Setup plugins table
local plugins = {}

-- ********************************************************************************
-- * Appearance                                                                   *
-- ********************************************************************************

-- Set diagnostic signs and colors
vim.diagnostic.config({
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = "",
			[vim.diagnostic.severity.WARN] = "",
			[vim.diagnostic.severity.INFO] = "",
			[vim.diagnostic.severity.HINT] = "",
		},
	},
	virtual_text = false,
	virtual_lines = { only_current_line = true, highlight_whole_line = false },
	underline = false,
	severity_sort = true,
})

-- Set colorscheme
table.insert(plugins, {
	"catppuccin/nvim",
	name = "catppuccin",
	priority = 1000,
	config = function()
		require("catppuccin").setup({
			integrations = {
				treesitter = true,
				harpoon = true,
				mini = {
					enabled = true,
					indentscope_color = "peach",
				},
				cmp = true,
				which_key = true,
				fidget = true,
				gitsigns = true,
				indent_blankline = {
					enabled = true,
					scope_color = "lavender",
					colored_indent_levels = false,
				},
				markdown = true,
				mason = true,
				noice = true,
				native_lsp = {
					enabled = true,
					virtual_text = {
						errors = { "italic" },
						hints = { "italic" },
						warnings = { "italic" },
						information = { "italic" },
						ok = { "italic" },
					},
					underlines = {
						errors = { "underline" },
						hints = { "underline" },
						warnings = { "underline" },
						information = { "underline" },
						ok = { "underline" },
					},
					inlay_hints = {
						background = true,
					},
				},
			},
		})
		vim.cmd.colorscheme("catppuccin-mocha")
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
		})
	end,
})

-- Add notifications
table.insert(plugins, {
	"j-hui/fidget.nvim",
	config = function()
		require("fidget").setup({
			notification = {
				window = {
					winblend = 0,
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
		local total_rows = vim.api.nvim_eval('winheight("$")')
		require("noice").setup({
			views = {
				cmdline_popup = {
					position = {
						row = total_rows - 1,
						col = "0%",
					},
					size = {
						width = "100%",
						height = "auto",
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

-- Scrollbar
table.insert(plugins, {
	"lewis6991/satellite.nvim",
	dependencies = { "lewis6991/gitsigns.nvim" },
	config = function()
		require("satellite").setup()
	end,
})

-- Lsp lines
table.insert(plugins, {
	"https://git.sr.ht/~whynothugo/lsp_lines.nvim",
	config = function()
		require("lsp_lines").setup()
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

-- ********************************************************************************
-- * Smart Splits                                                                 *
-- ********************************************************************************

-- Smart Splits
table.insert(plugins, {
	"mrjones2014/smart-splits.nvim",
	config = function()
		local smartsplits = require("smart-splits")
		smartsplits:setup({ jump = true })
		vim.keymap.set("n", "<Char-0xAA>", smartsplits.move_cursor_left)
		vim.keymap.set("n", "<Char-0xAB>", smartsplits.move_cursor_down)
		vim.keymap.set("n", "<Char-0xAC>", smartsplits.move_cursor_up)
		vim.keymap.set("n", "<Char-0xAD>", smartsplits.move_cursor_right)
		vim.keymap.set("n", "<Char-0xBA>", smartsplits.resize_left)
		vim.keymap.set("n", "<Char-0xBB>", smartsplits.resize_down)
		vim.keymap.set("n", "<Char-0xBC>", smartsplits.resize_up)
		vim.keymap.set("n", "<Char-0xBD>", smartsplits.resize_right)
	end,
})

-- ********************************************************************************
-- * Syntax Highlighting                                                          *
-- ********************************************************************************

-- Treesitter
table.insert(plugins, {
	"nvim-treesitter/nvim-treesitter",
	branch = "master",
	dependencies = { "windwp/nvim-ts-autotag" },
	event = { "BufReadPre", "BufNewFile" },
	run = ":TSUpdate",
	config = function()
		require("nvim-treesitter.configs").setup({
			sync_install = false,
			highlight = { enable = true },
			indent = { enable = true },
			autotag = { enable = true },
			additional_vim_regex_highlighting = true,
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "gnn",
					node_incremental = "grn",
					scope_incremental = "grc",
					node_decremental = "grm",
				},
			},
			auto_install = true,
			ensure_installed = {
				"vimdoc",
				"lua",
				"bash",
				"html",
				"css",
				"javascript",
				"typescript",
				"json",
				"markdown",
				"python",
				"gitignore",
				"angular",
				"c_sharp",
				"dockerfile",
				"java",
				"jq",
				"jsdoc",
				"kotlin",
				"latex",
				"scss",
				"sql",
				"yaml",
			},
		})
	end,
})

-- ********************************************************************************
-- * Language Servers                                                             *
-- ********************************************************************************

-- Lspconfig & Mason
table.insert(plugins, {
	"neovim/nvim-lspconfig",
	dependencies = {
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		"hrsh7th/cmp-nvim-lsp",
	},
	config = function()
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(event)
				local opts = { buffer = event.buf }
				vim.keymap.set(
					"n",
					"gk",
					vim.lsp.buf.hover,
					vim.tbl_extend("force", opts, { desc = "Hover documentation" })
				)
				vim.keymap.set(
					"n",
					"gd",
					vim.lsp.buf.definition,
					vim.tbl_extend("force", opts, { desc = "Go to definition" })
				)
				vim.keymap.set(
					"n",
					"gi",
					vim.lsp.buf.implementation,
					vim.tbl_extend("force", opts, { desc = "Go to implementation" })
				)
				vim.keymap.set(
					"n",
					"gr",
					vim.lsp.buf.references,
					vim.tbl_extend("force", opts, { desc = "Find references" })
				)
				vim.keymap.set(
					"n",
					"gs",
					vim.lsp.buf.signature_help,
					vim.tbl_extend("force", opts, { desc = "Signature help" })
				)
				vim.keymap.set(
					"n",
					"<leader>ca",
					vim.lsp.buf.code_action,
					vim.tbl_extend("force", opts, { desc = "Code action" })
				)
				vim.keymap.set(
					"n",
					"<leader>rn",
					vim.lsp.buf.rename,
					vim.tbl_extend("force", opts, { desc = "Rename" })
				)
			end,
		})
		local capabilities = require("cmp_nvim_lsp").default_capabilities()
		local default_setup = function(server)
			require("lspconfig")[server].setup({
				capabilities = capabilities,
			})
		end
		require("mason").setup({
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		})
		require("mason-lspconfig").setup({
			handlers = {
				default_setup,
				lua_ls = function()
					require("lspconfig").lua_ls.setup({
						capabilities = capabilities,
						settings = {
							Lua = {
								runtime = {
									version = "LuaJIT",
								},
								diagnostics = {
									globals = { "vim" },
								},
								workspace = {
									library = {
										vim.env.VIMRUNTIME,
										"${3rd}/luv/library",
									},
								},
							},
						},
					})
				end,
			},
			automatic_installation = true,
			ensure_installed = {
				"lua_ls",
				"tsserver",
				"html",
				"tailwindcss",
				"pyright",
				"angularls",
				"bashls",
				"omnisharp",
				"cssls",
				"dockerls",
				"docker_compose_language_service",
				"eslint",
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
				timeout_ms = 500,
				lsp_fallback = true,
			},
			formatters_by_ft = {
				lua = { "stylua" },
				javascript = { "prettier" },
				typescript = { "prettier" },
				typescriptreact = { "prettier" },
				javascriptreact = { "prettier" },
				html = { "prettier" },
				css = { "prettier" },
				json = { "prettier" },
				markdown = { "prettier" },
				python = { "black" },
				sh = { "shfmt" },
				yaml = { "prettier" },
				toml = { "prettier" },
				sql = { "sql-formatter" },
				java = { "google-java-format" },
				kotlin = { "ktlint" },
				zsh = { "shfmt" },
			},
		})
		vim.keymap.set({ "n", "v" }, "<leader>cf", function()
			require("conform").format({
				timeout_ms = 500,
				lsp_fallback = true,
			})
		end, { desc = "Format file or range (in visual mode)" })
		require("mason-conform").setup({
			automatic_installation = false,
			ensure_installed = {
				"stylua",
				"prettier",
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
		vim.keymap.set({ "n", "v" }, "<leader>cl", lint.try_lint, { desc = "Lint file" })
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
				{ name = "copilot", max_item_count = 3 },
				{ name = "nvim_lsp", max_item_count = 3 },
				{ name = "luasnip", max_item_count = 3 },
				{ name = "buffer", max_item_count = 3 },
				{ name = "path", max_item_count = 3 },
			},
			mapping = cmp.mapping.preset.insert({
				["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
				["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
				["<C-y>"] = cmp.mapping.confirm({ select = true }),
				["<C-Space>"] = cmp.mapping.complete(),
				["<Tab>"] = cmp.mapping.confirm(),
				["<C-e>"] = cmp.mapping({
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
		vim.keymap.set("n", "<leader>h", function()
			harpoon:list():add()
		end, { desc = "Add file to Harpoon" })
		vim.keymap.set("n", "<leader>d", function()
			harpoon.ui:toggle_quick_menu(harpoon:list())
		end, { desc = "Toggle Harpoon quick menu" })
		vim.keymap.set("n", "<C-h>", function()
			harpoon:list():select(1)
		end, { desc = "Select Harpoon mark 1" })
		vim.keymap.set("n", "<C-j>", function()
			harpoon:list():select(2)
		end, { desc = "Select Harpoon mark 2" })
		vim.keymap.set("n", "<C-k>", function()
			harpoon:list():select(3)
		end, { desc = "Select Harpoon mark 3" })
		vim.keymap.set("n", "<C-l>", function()
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
			delete_to_trash = true,
			view_options = {
				show_hidden = true,
			},
		})
		vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })
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
		vim.keymap.set({ "n", "v" }, "<leader>aa", copilotchat.toggle, { desc = "AI Toggle" })
		vim.api.nvim_create_autocmd("BufEnter", {
			pattern = "copilot-*",
			callback = function()
				vim.opt_local.relativenumber = false
				vim.opt_local.number = false
				vim.keymap.set(
					"n",
					"<C-s>",
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
		vim.o.timeout = true
		vim.o.timeoutlen = 300
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

-- Move with brackets
table.insert(plugins, {
	"echasnovski/mini.bracketed",
	version = false,
	config = function()
		require("mini.bracketed").setup()
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

-- Move text easily
table.insert(plugins, {
	"echasnovski/mini.move",
	version = false,
	config = function()
		require("mini.move").setup({
			mappings = {
				left = "<S-h>",
				right = "<S-l>",
				down = "<S-j>",
				up = "<S-k>",
				line_left = "<S-h>",
				line_right = "<S-l>",
				line_down = "<S-j>",
				line_up = "<S-k>",
			},
		})
	end,
})

-- Add precognition which assits discovering motions
table.insert(plugins, {
	"tris203/precognition.nvim",
	event = "VeryLazy",
	config = {
		startVisible = true,
		showBlankVirtLine = true,
		highlightColor = { link = "Comment" },
		hints = {
			Caret = { text = "^", prio = 2 },
			Dollar = { text = "$", prio = 1 },
			MatchingPair = { text = "%", prio = 5 },
			Zero = { text = "0", prio = 1 },
			w = { text = "w", prio = 10 },
			b = { text = "b", prio = 9 },
			e = { text = "e", prio = 8 },
			W = { text = "W", prio = 7 },
			B = { text = "B", prio = 6 },
			E = { text = "E", prio = 5 },
		},
		gutterHints = {
			G = { text = "G", prio = 10 },
			gg = { text = "gg", prio = 9 },
			PrevParagraph = { text = "{", prio = 8 },
			NextParagraph = { text = "}", prio = 8 },
		},
	},
})

-- Vim Be Good game
table.insert(plugins, {
	"ThePrimeagen/vim-be-good",
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
				vim.keymap.set("n", "<leader>gB", function()
					gitsigns.blame_line({ full = true })
				end, vim.tbl_extend("force", opts, { desc = "Blame line" }))
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
					":<C-U>Gitsigns select_hunk<cr>",
					vim.tbl_extend("force", opts, { desc = "Select hunk" })
				)
			end,
		})
	end,
})

-- Lazygit
table.insert(plugins, {
	"kdheepak/lazygit.nvim",
	requires = {
		"nvim-lua/plenary.nvim",
	},
	cmd = {
		"LazyGit",
		"LazyGitConfig",
		"LazyGitCurrentFile",
		"LazyGitFilter",
		"LazyGitFilterCurrentFile",
	},
	keys = {
		{ "<leader>gg", "<cmd>LazyGit<cr>", desc = "Open lazy git" },
	},
})

-- Load the lazy plugin manager and setup with the plugins table
require("lazy").setup(plugins, config)
