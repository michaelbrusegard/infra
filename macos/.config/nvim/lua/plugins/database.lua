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
	{
		"MattiasMTS/cmp-dbee",
		dependencies = {
			"kndndrj/nvim-dbee",
		},
		ft = "sql",
		config = function()
			require("cmp").setup.buffer({
				sources = {
					{ name = "cmp-dbee" },
				},
			})
		end,
	},
}
