return {
  -- lspconfig
	{
    "neovim/nvim-lspconfig",
    event = "LazyFile",
    dependencies = {
      "mason.nvim",
      "williamboman/mason-lspconfig.nvim",
			"hrsh7th/cmp-nvim-lsp",
		},
		opts = {
        -- Add any global capabilities here
        capabilities = {
          workspace = {
            fileOperations = {
              didRename = true,
              willRename = true,
            },
          },
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
			vim.api.nvim_create_autocmd('LspAttach', {
				callback = function(event)
				local client = vim.lsp.get_client_by_id(event.data.client_id)
					if client and client.supports_method("textDocument/inlayHint", { bufnr = event.buf }) then
						vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
					end
					if client and client.supports_method("textDocument/codeLens", { bufnr = event.buf }) then
						vim.lsp.codelens.refresh()
						vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
							buffer = event.buf,
							callback = vim.lsp.codelens.refresh,
						})
					end
					vim.keymap.set("n", "<leader>ci", "<cmd>LspInfo<cr>", { desc = "Lsp Info", buffer = event.buf })
					vim.keymap.set("n", "gd", "<cmd>lua require('util.navigation').pick('lsp_definitions', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "Goto Definition", buffer = event.buf })
					vim.keymap.set("n", "gr", "<cmd>lua require('util.navigation').pick('lsp_references', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "References", buffer = event.buf })
					vim.keymap.set("n", "gI", "<cmd>lua require('util.navigation').pick('lsp_implementations', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "Goto Implementation", buffer = event.buf })
					vim.keymap.set("n", "gy", "<cmd>lua require('util.navigation').pick('lsp_typedefs', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "Goto T[y]pe Definition", buffer = event.buf })
					vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { desc = "Goto Declaration", buffer = event.buf })
					vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover", buffer = event.buf })
					vim.keymap.set("n", "gK", vim.lsp.buf.signature_help, { desc = "Signature Help", buffer = event.buf })
					vim.keymap.set("i", "<c-k>", vim.lsp.buf.signature_help, { desc = "Signature Help", buffer = event.buf })
					vim.keymap.set({ "n", "x" }, "crr", vim.lsp.buf.code_action, { desc = "Code Action", buffer = event.buf })
					vim.keymap.set("n", "crn", vim.lsp.buf.rename, { desc = "Rename", buffer = event.buf })
					vim.keymap.set({ "n", "x" }, "<leader>cc", vim.lsp.codelens.run, { desc = "Run Codelens", buffer = event.buf })
					vim.keymap.set("n", "<leader>cC", vim.lsp.codelens.refresh, { desc = "Refresh & Display Codelens", buffer = event.buf })
				end
			})

      local capabilities = vim.tbl_deep_extend(
        "force",
        vim.lsp.protocol.make_client_capabilities(),
        require('cmp_nvim_lsp').default_capabilities(),
        opts.capabilities
      )

			local function setup(server)
        local server_opts = vim.tbl_deep_extend("force", {
          capabilities = vim.deepcopy(capabilities),
        }, opts.servers[server] or {})

        if opts.setup[server] then
          if opts.setup[server](server, server_opts) then
            return
          end
        end
        require("lspconfig")[server].setup(server_opts)
      end

			-- Get all the servers that are available through mason-lspconfig
      local ensure_installed = {}
      for server, server_opts in pairs(opts.servers) do
        if server_opts then
					ensure_installed[#ensure_installed + 1] = server
				end
      end

      require('mason-lspconfig').setup({
        ensure_installed,
        handlers = { setup },
      })
		end
	},
  -- More readable diagnostics
	{
		"rachartier/tiny-inline-diagnostic.nvim",
		event = "VeryLazy",
		opts = {
      -- Options for vim.diagnostic.config()
      diagnostic = {
        underline = true,
        update_in_insert = false,
        virtual_text = false,
        severity_sort = true,
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = ' ',
            [vim.diagnostic.severity.WARN] = ' ',
            [vim.diagnostic.severity.HINT] = ' ',
            [vim.diagnostic.severity.INFO] = ' ',
          },
        },
      },
    },
    config = function(_, opts)
			require('tiny-inline-diagnostic').setup()
      vim.diagnostic.config(opts.diagnostic)
    end
	},
	-- Cmdline tools and lsp servers
	{
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
			local mr = require("mason-registry")
			mr:on("package:install:success", function()
				vim.defer_fn(function()
					-- trigger FileType event to possibly load this newly installed LSP server
					require("lazy.core.handler.event").trigger({
						event = "FileType",
						buf = vim.api.nvim_get_current_buf(),
					})
				end, 100)
			end)

			mr.refresh(function()
				for _, tool in ipairs(opts.ensure_installed) do
					local p = mr.get_package(tool)
					if not p:is_installed() then
						p:install()
					end
				end
			end)
		end,
	},
}
