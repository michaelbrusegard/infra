return {
	-- auto pairs
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
			require("util.mini").pairs(opts)
		end,
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
					i = require("util.mini").ai_indent,
					g = require("util.mini").ai_buffer,
					u = ai.gen_spec.function_call(),
					U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
				},
			}
		end,
		config = function(_, opts)
			require("mini.ai").setup(opts)
			require("util.lazy").on_load("which-key.nvim", function()
				vim.schedule(function()
					require("util.mini").ai_whichkey(opts)
				end)
			end)
		end,
	},
	-- Move selected text
	{
		"echasnovski/mini.move",
    event = "VeryLazy",
		version = false,
		opts = {
			mappings = {
				left = "<s-h>",
				right = "<s-l>",
				down = "<s-j>",
				up = "<s-k>",
				line_left = "",
				line_right = "",
				line_down = "",
				line_up = "",
			},
			options = {
				reindent_linewise = true,
			},
		},
	},
  -- Add surround keymaps
  {
    'echasnovski/mini.surround',
    event = "VeryLazy",
    version = false,
    keys = {
        { 'gsa', desc = "Add Surrounding", mode = { "n", "v" } },
        { 'gsd', desc = "Delete Surrounding" },
        { 'gsf', desc = "Find Right Surrounding" },
        { 'gsF', desc = "Find Left Surrounding" },
        { 'gsH', desc = "Highlight Surrounding" },
        { 'gsr', desc = "Replace Surrounding" },
        { 'gsn', desc = "Update `MiniSurround.config.n_lines`" },
    },
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
}
