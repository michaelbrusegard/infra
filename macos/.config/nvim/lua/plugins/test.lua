return {
	{
		"nvim-neotest/neotest",
		dependencies = { "nvim-neotest/nvim-nio" },
		opts = {
			-- Can be a list of adapters like what neotest expects,
			-- or a list of adapter names,
			-- or a table of adapter names, mapped to adapter configs.
			-- The adapter will then be automatically loaded with the config.
			adapters = {},
			-- Example for loading neotest-golang with a custom config
			-- adapters = {
			--   ["neotest-golang"] = {
			--     go_test_args = { "-v", "-race", "-count=1", "-timeout=60s" },
			--     dap_go_enabled = true,
			--   },
			-- },
			status = { virtual_text = true },
			output = { open_on_run = true },
			quickfix = {
				open = function()
					require("trouble").open({ mode = "quickfix", focus = false })
				end,
			},
		},
		config = function(_, opts)
			local neotest_ns = vim.api.nvim_create_namespace("neotest")
			vim.diagnostic.config({
				virtual_text = {
					format = function(diagnostic)
						-- Replace newline and tab characters with space for more compact diagnostics
						local message =
							diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
						return message
					end,
				},
			}, neotest_ns)

			opts.consumers = opts.consumers or {}

			opts.consumers.trouble = function(client)
				client.listeners.results = function(adapter_id, results, partial)
					if partial then
						return
					end
					local tree = assert(client:get_position(nil, { adapter = adapter_id }))

					local failed = 0
					for pos_id, result in pairs(results) do
						if result.status == "failed" and tree:get_key(pos_id) then
							failed = failed + 1
						end
						vim.schedule(function()
							local trouble = require("trouble")
							if trouble.is_open() then
								trouble.refresh()
								if failed == 0 then
									trouble.close()
								end
							end
						end)
						return {}
					end
				end
			end

			if opts.adapters then
				local adapters = {}
				for name, config in pairs(opts.adapters or {}) do
					if type(name) == "number" then
						if type(config) == "string" then
							config = require(config)
						end
						adapters[#adapters + 1] = config
					elseif config ~= false then
						local adapter = require(name)
						if type(config) == "table" and not vim.tbl_isempty(config) then
							local meta = getmetatable(adapter)
							if adapter.setup then
								adapter.setup(config)
							elseif adapter.adapter then
								adapter.adapter(config)
								adapter = adapter.adapter
							elseif meta and meta.__call then
								adapter(config)
							else
								error("Adapter " .. name .. " does not support setup")
							end
						end
						adapters[#adapters + 1] = adapter
					end
				end
				opts.adapters = adapters
			end

			require("neotest").setup(opts)
		end,
    -- stylua: ignore
    keys = {
      {"<leader>t", "", desc = "+test"},
      { "<leader>tt", "<cmd>lua require('neotest').run.run(vim.fn.expand('%'))<cr>", desc = "Run File" },
      { "<leader>tT", "<cmd>lua require('neotest').run.run(vim.uv.cwd())<cr>", desc = "Run All Test Files" },
      { "<leader>tr", "<cmd>lua require('neotest').run.run()<cr>", desc = "Run Nearest" },
      { "<leader>tl", "<cmd>lua require('neotest').run.run_last()<cr>", desc = "Run Last" },
      { "<leader>ts", "<cmd>lua require('neotest').summary.toggle()<cr>", desc = "Toggle Summary" },
      { "<leader>to", "<cmd>lua require('neotest').output.open({ enter = true, auto_close = true })<cr>", desc = "Show Output" },
      { "<leader>tO", "<cmd>lua require('neotest').output_panel.toggle()<cr>", desc = "Toggle Output Panel" },
      { "<leader>tS", "<cmd>lua require('neotest').run.stop()<cr>", desc = "Stop" },
      { "<leader>tw", "<cmd>lua require('neotest').watch.toggle(vim.fn.expand('%'))<cr>", desc = "Toggle Watch" },
    },
	},
	{
		"mfussenegger/nvim-dap",
		optional = true,
		keys = {
			{
				"<leader>td",
				"<cmd>lua require('neotest').run.run({ strategy = 'dap' })<cr>",
				desc = "Debug Nearest",
			},
		},
	},
}
