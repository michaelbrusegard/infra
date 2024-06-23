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

-- Go to next diagnostic message
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic message" })

-- Go to previous diagnostic message
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic message" })

-- Move selected lines up and down
vim.keymap.set("v", "J", ":move '>+1<CR>gv-gv", { desc = "Move selected lines down" })
vim.keymap.set("v", "K", ":move '<-2<CR>gv-gv", { desc = "Move selected lines up" })

-- Keep selection when indenting
vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")

-- Open mason
vim.api.nvim_set_keymap("n", "<leader>m", ":Mason<CR>", { desc = "Open Mason" })

-- Open lazy
vim.api.nvim_set_keymap("n", "<leader>l", ":Lazy<CR>", { desc = "Open Lazy" })

-- Save file
vim.api.nvim_set_keymap("n", "<leader>w", ":w<CR>", { desc = "Save file" })

-- Quit file
vim.api.nvim_set_keymap("n", "<leader>q", ":q<CR>", { desc = "Quit file" })

-- Save and quit file
vim.api.nvim_set_keymap("n", "<leader>x", ":x<CR>", { desc = "Save and quit file" })

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
	virtual_text = {
		spacing = 4,
		style = "italic,bold",
		prefix = function(diagnostic)
			local icons = {
				[vim.diagnostic.severity.ERROR] = "",
				[vim.diagnostic.severity.WARN] = "",
				[vim.diagnostic.severity.INFO] = "",
				[vim.diagnostic.severity.HINT] = "",
			}
			return icons[diagnostic.severity] .. " "
		end,
	},
	underline = {
		severity = {
			min = vim.diagnostic.severity.WARN,
		},
	},
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
				telescope = {
					enabled = true,
				},
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
				mason = true,
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
			auto_install = true,
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
		"WhoIsSethDaniel/mason-tool-installer.nvim",
	},
	config = function()
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(event)
				local opts = { buffer = event.buf }
				vim.keymap.set(
					"n",
					"K",
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
			automatic_installation = true,
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
			ensure_installed = {
				"lua_ls",
				"tsserver",
				"html",
				"tailwindcss",
				"pyright",
			},
		})
		require("mason-tool-installer").setup({
			auto_update = true,
			run_on_start = true,
			ensure_installed = {
				"stylua",
				"luacheck",
				"prettier",
				"eslint_d",
				"black",
				"jsonlint",
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

-- Telescope
table.insert(plugins, {
	"nvim-telescope/telescope.nvim",
	branch = "0.1.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
	},
	config = function()
		local telescope = require("telescope")
		local builtin = require("telescope.builtin")
		vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
		vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
		vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
		vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Find help tags" })
		telescope.setup()
		telescope.load_extension("fzf")
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
		vim.keymap.set("n", "<leader>a", function()
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
		})
		vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
	end,
})

-- ********************************************************************************
-- * Linting & Formatting                                                         *
-- ********************************************************************************

-- Conform
table.insert(plugins, {
	"stevearc/conform.nvim",
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
				go = { "gofmt" },
				rust = { "rustfmt" },
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
	end,
})

-- Nvim Lint
table.insert(plugins, {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			lua = { "luacheck" },
			javascript = { "eslint_d" },
			typescript = { "eslint_d" },
			typescriptreact = { "eslint_d" },
			javascriptreact = { "eslint_d" },
			html = { "tidy" },
			css = { "stylelint" },
			json = { "jsonlint" },
			markdown = { "markdownlint" },
			python = { "flake8" },
			go = { "golangci-lint" },
			rust = { "clippy" },
			sh = { "shellcheck" },
			yaml = { "yamllint" },
			toml = { "tlint" },
			sql = { "sqlint" },
			java = { "checkstyle" },
			kotlin = { "ktlint" },
			zsh = { "shellcheck" },
		}
		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave", "TextChanged" }, {
			callback = function()
				lint.try_lint()
			end,
		})
		vim.keymap.set("n", "<leader>cl", lint.try_lint, { desc = "Lint file" })
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
	keys = {
		{
			"<leader>ccb",
			function()
				vim.cmd("CopilotChatOpen")
				vim.defer_fn(function()
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>l", true, false, true), "n", false)
				end, 50)
			end,
			mode = { "n", "v" },
			desc = "CopilotChat - Open and jump into",
		},
		{ "<leader>cce", "<cmd>CopilotChatExplain<cr>", mode = { "n", "v" }, desc = "CopilotChat - Explain code" },
		{ "<leader>cct", "<cmd>CopilotChatTests<cr>", mode = { "n", "v" }, desc = "CopilotChat - Generate tests" },
		{ "<leader>ccr", "<cmd>CopilotChatReview<cr>", mode = { "n", "v" }, desc = "CopilotChat - Review code" },
		{ "<leader>ccR", "<cmd>CopilotChatRefactor<cr>", mode = { "n", "v" }, desc = "CopilotChat - Refactor code" },
		{ "<leader>cco", "<cmd>CopilotChatOptimize<cr>", mode = { "n", "v" }, desc = "CopilotChat - Optimize code" },
		{
			"<leader>ccq",
			function()
				local input = vim.fn.input("Quick Chat: ")
				if input ~= "" then
					require("CopilotChat").ask(input, { selection = require("CopilotChat.select").buffer })
				end
			end,
			mode = { "n", "v" },
			desc = "CopilotChat - Quick chat",
		},
	},
	event = "VeryLazy",
	config = function()
		require("CopilotChat.integrations.cmp").setup()
		require("CopilotChat").setup({
			window = {
				width = 0.4,
			},
			mappings = {
				complete = {
					insert = "",
				},
			},
		})
		local function stop_copilot_chat()
			pcall(vim.cmd, "CopilotChatStop")
		end
		vim.api.nvim_create_autocmd("BufEnter", {
			pattern = "copilot-*",
			callback = function()
				vim.keymap.set("n", "<C-s>", stop_copilot_chat, { buffer = true, desc = "CopilotChat - Stop output" })
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

-- Auto pairs
table.insert(plugins, {
	"echasnovski/mini.pairs",
	version = false,
	config = function()
		require("mini.pairs").setup()
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

-- ********************************************************************************
-- * Git                                                                          *
-- ********************************************************************************

-- Gitsigns
table.insert(plugins, {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		on_attach = function(bufnr)
			local gitsigns = require("gitsigns")
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
			vim.keymap.set("n", "<leader>gd", gitsigns.diffthis, vim.tbl_extend("force", opts, { desc = "Diff this" }))
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
				":<C-U>Gitsigns select_hunk<CR>",
				vim.tbl_extend("force", opts, { desc = "Select hunk" })
			)
		end,
	},
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
