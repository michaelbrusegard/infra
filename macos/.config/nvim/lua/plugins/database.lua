return {
	-- Database client
	{
		"kndndrj/nvim-dbee",
		dependencies = {
			"MunifTanjim/nui.nvim",
		},
		build = function()
			-- Install tries to automatically detect the install method.
			-- if it fails, try calling it with one of these parameters:
			--    "curl", "wget", "bitsadmin", "go"
			require("dbee").install()
		end,
		keys = {
			{ "<leader>D", "<cmd>lua require('dbee').toggle()<cr>", desc = "Database UI" },
		},
		opts = {},
	},
	-- Completion integration
	-- {
	-- 	"nvim-cmp",
	-- 	dependencies = {
	-- 		{
	-- 			"MattiasMTS/cmp-dbee",
	-- 			dependencies = {
	-- 				{ "kndndrj/nvim-dbee" },
	-- 			},
	-- 			ft = "sql",
	-- 			opts = {},
	-- 		},
	-- 	},
	-- 	opts = {
	-- 		sources = {
	-- 			{ "cmp-dbee" },
	-- 		},
	-- 	},
	-- },
}
