return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			-- virtual text for the debugger
			{
				"theHamsta/nvim-dap-virtual-text",
				opts = {},
			},
		},
    -- stylua: ignore
    keys = {
      { "<leader>d", "", desc = "+debug", mode = {"n", "x"} },
      { "<leader>dB", "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))<cr>", desc = "Breakpoint Condition" },
      { "<leader>db", "<cmd>lua require('dap').toggle_breakpoint()<cr>", desc = "Toggle Breakpoint" },
      { "<leader>dc", "<cmd>lua require('dap').continue()<cr>", desc = "Continue" },
      { "<leader>da", "<cmd>lua require('dap').continue({ before = require('util.debug').get_args() })<cr>", desc = "Run with Args" },
      { "<leader>dC", "<cmd>lua require('dap').run_to_cursor()<cr>", desc = "Run to Cursor" },
      { "<leader>dg", "<cmd>lua require('dap').goto_()<cr>", desc = "Go to Line (No Execute)" },
      { "<leader>di", "<cmd>lua require('dap').step_into()<cr>", desc = "Step Into" },
      { "<leader>dj", "<cmd>lua require('dap').down()<cr>", desc = "Down" },
      { "<leader>dk", "<cmd>lua require('dap').up()<cr>", desc = "Up" },
      { "<leader>dl", "<cmd>lua require('dap').run_last()<cr>", desc = "Run Last" },
      { "<leader>do", "<cmd>lua require('dap').step_out()<cr>", desc = "Step Out" },
      { "<leader>dO", "<cmd>lua require('dap').step_over()<cr>", desc = "Step Over" },
      { "<leader>dp", "<cmd>lua require('dap').pause()<cr>", desc = "Pause" },
      { "<leader>dr", "<cmd>lua require('dap').repl.toggle()<cr>", desc = "Toggle REPL" },
      { "<leader>ds", "<cmd>lua require('dap').session()<cr>", desc = "Session" },
      { "<leader>dt", "<cmd>lua require('dap').terminate()<cr>", desc = "Terminate" },
      { "<leader>dw", "<cmd>lua require('dap.ui.widgets').hover()<cr>", desc = "Widgets" },
    },
		config = function()
			-- load mason-nvim-dap here, after all adapters have been setup
			require("mason-nvim-dap").setup(require("util.lazy").opts("mason-nvim-dap.nvim"))

			vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

			local icons = {
				Stopped = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
				Breakpoint = " ",
				BreakpointCondition = " ",
				BreakpointRejected = { " ", "DiagnosticError" },
				LogPoint = ".>",
			}

			for name, sign in pairs(icons) do
				sign = type(sign) == "table" and sign or { sign }
				vim.fn.sign_define(
					"Dap" .. name,
					{ text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
				)
			end
		end,
	},
	-- Fancy UI for the debugger
	{
		"rcarriga/nvim-dap-ui",
		dependencies = { "nvim-neotest/nvim-nio" },
    -- stylua: ignore
    keys = {
      { "<leader>du", function() require("dapui").toggle({ }) end, desc = "Dap UI" },
      { "<leader>de", function() require("dapui").eval() end, desc = "Eval", mode = {"n", "v"} },
    },
		opts = {},
		config = function(_, opts)
			local dap = require("dap")
			local dapui = require("dapui")
			dapui.setup(opts)
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open({})
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close({})
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close({})
			end
		end,
	},
	-- Mason.nvim integration
	{
		"jay-babu/mason-nvim-dap.nvim",
		dependencies = "mason.nvim",
		cmd = { "DapInstall", "DapUninstall" },
		opts = {
			-- Makes a best effort to setup the various debuggers with
			-- reasonable debug configurations
			automatic_installation = true,

			-- You can provide additional configuration to the handlers,
			-- see mason-nvim-dap README for more information
			handlers = {},

			-- You'll need to check that you have the required things installed
			-- online, please don't ask me how to install them :)
			ensure_installed = {
				-- Update this to ensure that you have the debuggers for the langs you want
			},
		},
		-- mason-nvim-dap is loaded when nvim-dap loads
		config = function() end,
	},
	-- Nvim lua dap
	{
		"nvim-dap",
		dependencies = {
			{
				"jbyuki/one-small-step-for-vimkind",
      -- stylua: ignore
      config = function()
        local dap = require("dap")
        dap.adapters.nlua = function(callback, conf)
          local adapter = {
            type = "server",
            host = conf.host or "127.0.0.1",
            port = conf.port or 8086,
          }
          if conf.start_neovim then
            local dap_run = dap.run
            dap.run = function(c)
              adapter.port = c.port
              adapter.host = c.host
            end
            require("osv").run_this()
            dap.run = dap_run
          end
          callback(adapter)
        end
        dap.configurations.lua = {
          {
            type = "nlua",
            request = "attach",
            name = "Run this file",
            start_neovim = {},
          },
          {
            type = "nlua",
            request = "attach",
            name = "Attach to running Neovim instance (port = 8086)",
            port = 8086,
          },
        }
      end,
			},
		},
	},
}
