return {
	-- Search/replace in multiple files
	{
		"MagicDuck/grug-far.nvim",
		opts = { headerMaxWidth = 80 },
		cmd = "GrugFar",
		keys = {
			{
				"<leader>sr",
				function()
					local is_visual = vim.fn.mode():lower():find("v")
					if is_visual then -- needed to make visual selection work
						vim.cmd([[normal! v]])
					end
					local grug = require("grug-far")
					local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
					local filesFilter = ext and ext ~= "" and "*." .. ext or nil;
					(is_visual and grug.with_visual_selection or grug.grug_far)({
						prefills = { filesFilter = filesFilter },
					})
				end,
				mode = { "n", "v" },
				desc = "Search and Replace",
			},
		},
	},
  -- Flash enhances the built-in search functionality by showing labels
  -- at the end of each match, letting you quickly jump to a specific
  -- location.
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, "<cmd>lua require('flash').jump()<cr>", desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, "<cmd>lua require('flash').treesitter()<cr>", desc = "Flash Treesitter" },
      { "r", mode = "o", "<cmd>lua require('flash').remote()<cr>", desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, "<cmd>lua function() require('flash').treesitter_search()<cr>", desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" }, "<cmd>lua require('flash').toggle()<cr>", desc = "Toggle Flash Search" },
    },
  },
	-- which-key helps you remember key bindings by showing a popup
	-- with the active keybindings of the command you started typing.
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts_extend = { "spec" },
		opts = {
			defaults = {},
			spec = {
				{
					mode = { "n", "v" },
					{ "<leader>c", group = "code" },
					{ "<leader>f", group = "file/find" },
					{ "<leader>g", group = "git" },
					{ "<leader>s", group = "search" },
					{ "<leader>u", group = "ui", icon = { icon = "󰙵 ", color = "cyan" } },
					{ "<leader>x", group = "trouble", icon = { icon = "󱖫 ", color = "green" } },
					{ "[", group = "prev" },
					{ "]", group = "next" },
					{ "g", group = "goto" },
					{ "s", group = "surround" },
					{ "z", group = "fold" },
					{
						"<leader>b",
						group = "buffer",
						expand = function()
							return require("which-key.extras").expand.buf()
						end,
					},
					{
						"<leader>w",
						group = "windows",
						proxy = "<c-w>",
						expand = function()
							return require("which-key.extras").expand.win()
						end,
					},
				},
			},
		},
		keys = {
			{
				"<leader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Keymaps",
			},
			{
				"<c-w><space>",
				function()
					require("which-key").show({ keys = "<c-w>", loop = true })
				end,
				desc = "Window Hydra Mode",
			},
		},
		config = function(_, opts)
			local wk = require("which-key")
			wk.setup(opts)
		end,
	},
  -- Show git signs in the sign column
	{
		"lewis6991/gitsigns.nvim",
		event = "LazyFile",
		opts = {
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			signs_staged = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
			},
			on_attach = function(buffer)
				local gs = package.loaded.gitsigns

				local function map(mode, l, r, desc)
					vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
				end

        -- stylua: ignore start
        map("n", "]g", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Git Next Hunk")
        map("n", "[g", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Git Prev Hunk")
        map("n", "]G", function() gs.nav_hunk("last") end, "Git Last Hunk")
        map("n", "[G", function() gs.nav_hunk("first") end, "Git First Hunk")
        map({ "n", "v" }, "<leader>gs", ":Gitsigns stage_hunk<cr>", "Git Stage Hunk")
        map({ "n", "v" }, "<leader>gr", ":Gitsigns reset_hunk<cr>", "Git Reset Hunk")
        map("n", "<leader>gS", gs.stage_buffer, "Git Stage Buffer")
        map("n", "<leader>gu", gs.undo_stage_hunk, "Git Undo Stage Hunk")
        map("n", "<leader>gR", gs.reset_buffer, "Git Reset Buffer")
        map("n", "<leader>gp", gs.preview_hunk_inline, "Git Preview Hunk Inline")
        map("n", "<leader>gb", function() gs.blame_line() end, "Git Blame Line")
        map("n", "<leader>gd", gs.diffthis, "Git Diff This")
        map("n", "<leader>gD", function() gs.diffthis("~") end, "Git Diff This ~")
        map({ "o", "x" }, "ih", ":<c-U>Gitsigns select_hunk<cr>", "Git Select Hunk")
			end,
		},
	},
	-- Better diagnostics list and others
	{
		"folke/trouble.nvim",
		cmd = { "Trouble" },
		opts = {
			modes = {
				lsp = {
					win = { position = "right" },
				},
			},
		},
		keys = {
			{ "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
			{ "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics" },
			{ "<leader>cs", "<cmd>Trouble symbols toggle<cr>", desc = "Symbols" },
			{ "<leader>cS", "<cmd>Trouble lsp toggle<cr>", desc = "LSP References" },
			{ "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "Location List" },
			{ "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix List" },
			{
				"[q",
				function()
					if require("trouble").is_open() then
						require("trouble").prev({ skip_groups = true, jump = true })
					else
						local ok, err = pcall(vim.cmd.cprev)
						if not ok then
							vim.notify(err, vim.log.levels.ERROR)
						end
					end
				end,
				desc = "Previous Quickfix Item",
			},
			{
				"]q",
				function()
					if require("trouble").is_open() then
						require("trouble").next({ skip_groups = true, jump = true })
					else
						local ok, err = pcall(vim.cmd.cnext)
						if not ok then
							vim.notify(err, vim.log.levels.ERROR)
						end
					end
				end,
				desc = "Next Quickfix Item",
			},
		},
	},
	-- Finds and lists all of the TODO, HACK, BUG, etc comment
	-- in your project and loads them into a browsable list.
	{
		"folke/todo-comments.nvim",
		cmd = { "TodoTrouble" },
		event = "LazyFile",
		opts = {},
    -- stylua: ignore
    keys = {
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next Todo Comment" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous Todo Comment" },
      { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Todo" },
      { "<leader>xT", "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>", desc = "Filter Todo/Fix/Fixme" },
    },
	},
  -- Remove search highlights when moving
	{
		"nvimdev/hlsearch.nvim",
		event = "BufRead",
		opts = {},
	},
  -- Set shiftwidth based on what is used in project
  {
    'nmac427/guess-indent.nvim',
    event = 'LazyFile',
    opts = {
      filetype_exclude = {
        "oil",
        "copilot-chat",
      },
    },
  },
}
