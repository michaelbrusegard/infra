return {
	-- Fuzzy finder
	{
		"ibhagwan/fzf-lua",
		cmd = "FzfLua",
		opts = function()
			local config = require("fzf-lua.config")

			-- Quickfix
			config.defaults.keymap.fzf["ctrl-q"] = "select-all+accept"
			config.defaults.keymap.fzf["ctrl-u"] = "half-page-up"
			config.defaults.keymap.fzf["ctrl-d"] = "half-page-down"
			config.defaults.keymap.fzf["ctrl-x"] = "jump"
			config.defaults.keymap.fzf["ctrl-f"] = "preview-page-down"
			config.defaults.keymap.fzf["ctrl-b"] = "preview-page-up"
			config.defaults.keymap.builtin["<c-f>"] = "preview-page-down"
			config.defaults.keymap.builtin["<c-b>"] = "preview-page-up"

			-- Trouble
			config.defaults.actions.files["ctrl-t"] = require("trouble.sources.fzf").actions.open

			-- Toggle root dir / cwd
			config.defaults.actions.files["ctrl-r"] = function(_, ctx)
				local opts = vim.deepcopy(ctx.__call_opts)
				opts.root = opts.root == false
				opts.cwd = nil
				opts.buf = ctx.__CTX.bufnr
				require("util.navigation").pick(ctx.__INFO.cmd, opts)
			end
			config.set_action_helpstr(config.defaults.actions.files["ctrl-r"], "toggle-root-dir")

			-- Use the same prompt for all
			local defaults = require("fzf-lua.profiles.default-title")
			local function fix(t)
				t.prompt = t.prompt ~= nil and "" or nil
				for _, v in pairs(t) do
					if type(v) == "table" then
						fix(v)
					end
				end
			end
			fix(defaults)

			local img_previewer = { "chafa", "-f", "symbols" }

			return vim.tbl_deep_extend("force", defaults, {
				fzf_colors = true,
				fzf_opts = {
					["--no-scrollbar"] = true,
				},
				defaults = {
					formatter = "path.dirname_first",
				},
				previewers = {
					bat = {
						cmd = "bat",
						args = "",
						theme = nil,
						config = nil,
					},
					builtin = {
						extensions = {
							["svg"] = img_previewer,
							["png"] = img_previewer,
							["jpg"] = img_previewer,
							["jpeg"] = img_previewer,
							["gif"] = img_previewer,
							["webp"] = img_previewer,
						},
					},
				},
				-- Configure vim.ui.select
				ui_select = function(fzf_opts, items)
					return vim.tbl_deep_extend("force", fzf_opts, {
						prompt = "",
						winopts = {
							title = " " .. vim.trim((fzf_opts.prompt or "Select"):gsub("%s*:%s*$", "")) .. " ",
							title_pos = "center",
						},
					}, fzf_opts.kind == "codeaction" and {
						winopts = {
							layout = "vertical",
							-- height is number of items minus 15 lines for the preview, with a max of 80% screen height
							height = math.floor(math.min(vim.o.lines * 0.8 - 16, #items + 2) + 0.5) + 16,
							width = 0.5,
							preview = not false and {
								layout = "vertical",
								vertical = "down:15,border-top",
								hidden = "hidden",
							} or {
								layout = "vertical",
								vertical = "down:15,border-top",
							},
						},
					} or {
						winopts = {
							width = 0.5,
							-- height is number of items, with a max of 80% screen height
							height = math.floor(math.min(vim.o.lines * 0.8, #items + 2) + 0.5),
						},
					})
				end,
				winopts = {
					width = 0.85,
					height = 0.85,
					row = 0.5,
					col = 0.5,
					backdrop = 100,
					preview = {
						scrollchars = { "┃", "" },
					},
				},
				files = {
					cwd_prompt = false,
					cmd = vim.env.FZF_CTRL_T_COMMAND .. " --type f",
				},
				buffers = {
					sort_mru = true,
					sort_lastused = true,
				},
				lsp = {
					symbols = {
						symbol_hl = function(s)
							return "TroubleIcon" .. s
						end,
						symbol_fmt = function(s)
							return s:lower() .. "\t"
						end,
						child_prefix = false,
					},
					code_actions = {
						previewer = true,
					},
				},
			})
		end,
		config = function(_, opts)
			require("fzf-lua").setup(opts)
		end,
		init = function()
			require("util.lazy").on_very_lazy(function()
				vim.ui.select = function(...)
					require("lazy").load({ plugins = { "fzf-lua" } })
					local opts = require("util.lazy").opts("fzf-lua") or {}
					require("fzf-lua").register_ui_select(opts.ui_select or nil)
					return vim.ui.select(...)
				end
			end)
		end,
		keys = {
			{ "<c-j>", "<c-j>", ft = "fzf", mode = "t", nowait = true },
			{ "<c-k>", "<c-k>", ft = "fzf", mode = "t", nowait = true },
			{
				"<leader>,",
				"<cmd>FzfLua buffers sort_mru=true sort_lastused=true<cr>",
				desc = "Switch Buffer",
			},
			{ "<leader>/", "<cmd>lua require('util.navigation').pick('live_grep')<cr>", desc = "Grep" },
			{
				"<leader>:",
				"<cmd>lua require('util.navigation').pick('command_history')<cr>",
				desc = "Command History",
			},
			{ "<leader><space>", "<cmd>lua require('util.navigation').pick('files')<cr>", desc = "Find Files" },
			-- Find
			{ "<leader>fb", "<cmd>lua require('util.navigation').pick('buffers')<cr>", desc = "Buffers" },
			{ "<leader>ff", "<cmd>lua require('util.navigation').pick('files')<cr>", desc = "Find Files" },
			{ "<leader>fg", "<cmd>lua require('util.navigation').pick('live_grep')<cr>", desc = "Grep" },
			{
				"<leader>fg",
				"<cmd>lua require('util.navigation').pick('grep_visual')<cr>",
				mode = "v",
				desc = "Selection (Root Dir)",
			},
			{ "<leader>fr", "<cmd>lua require('util.navigation').pick('oldfiles')<cr>", desc = "Recent" },
			-- Git
			{ "<leader>gc", "<cmd>lua require('util.navigation').pick('git_commits')<cr>", desc = "Git Commits" },
			-- Search
			{ '<leader>s"', "<cmd>lua require('util.navigation').pick('registers')<cr>", desc = "Registers" },
			{ "<leader>sc", "<cmd>lua require('util.navigation').pick('commands')<cr>", desc = "Commands" },
			{
				"<leader>sC",
				"<cmd>lua require('util.navigation').pick('command_history')<cr>",
				desc = "Command History",
			},
			{
				"<leader>sd",
				"<cmd>lua require('util.navigation').pick('diagnostics_document')<cr>",
				desc = "Document Diagnostics",
			},
			{ "<leader>sh", "<cmd>lua require('util.navigation').pick('help_tags')<cr>", desc = "Help Pages" },
		},
	},
	-- File explorer
	{
		"stevearc/oil.nvim",
		dependencies = { "echasnovski/mini.icons" },
		keys = {
			{
				"-",
				function()
					local ft = vim.bo.filetype
					if ft ~= "lazy" and ft ~= "mason" and ft ~= "git" then
						vim.cmd("Oil")
					end
				end,
				desc = "Open parent directory",
			},
		},
		opts = {
			default_file_explorer = true,
			delete_to_trash = true,
			skip_confirm_for_simple_edits = true,
			view_options = {
				show_hidden = true,
				natural_order = true,
				is_always_hidden = function(name, _)
					return name == ".." or name == ".git" or name == ".DS_Store"
				end,
			},
		},
	},
	-- Pane navigation
	{
		"mrjones2014/smart-splits.nvim",
		opts = {},
	},
	-- Harpoon quick navigation
	{
		"ThePrimeagen/harpoon",
		branch = "harpoon2",
		opts = {
			menu = {
				width = vim.api.nvim_win_get_width(0) - 4,
			},
			settings = {
				save_on_toggle = true,
			},
		},
		keys = {
			{
				"<leader>H",
				"<cmd>lua require('harpoon'):list():add()<cr>",
				desc = "Harpoon File",
			},
			{
				"<leader>h",
				function()
					if vim.g.float_open then
						return
					end
					vim.g.float_open = true
					require("harpoon").ui:toggle_quick_menu(require("harpoon"):list())
				end,
				desc = "Harpoon Quick Menu",
			},
			{
				"<c-h>",
				"<cmd>lua require('harpoon'):list():select(1)<cr>",
				desc = "Harpoon Quick Menu",
			},
			{
				"<c-j>",
				"<cmd>lua require('harpoon'):list():select(2)<cr>",
				desc = "Harpoon Quick Menu",
			},
			{
				"<c-k>",
				"<cmd>lua require('harpoon'):list():select(3)<cr>",
				desc = "Harpoon Quick Menu",
			},
			{
				"<c-l>",
				"<cmd>lua require('harpoon'):list():select(4)<cr>",
				desc = "Harpoon Quick Menu",
			},
		},
	},
}
