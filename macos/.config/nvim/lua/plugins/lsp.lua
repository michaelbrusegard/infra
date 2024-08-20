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
			-- Options for vim.diagnostic.config()
			diagnostic = {
				underline = true,
				update_in_insert = false,
				virtual_text = false,
				severity_sort = true,
				signs = {
					text = {
						[vim.diagnostic.severity.ERROR] = " ",
						[vim.diagnostic.severity.WARN] = " ",
						[vim.diagnostic.severity.HINT] = " ",
						[vim.diagnostic.severity.INFO] = " ",
					},
				},
				virtual_lines = {
					only_current_line = true,
					highlight_whole_line = false,
				},
			},
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
				vtsls = {
					-- explicitly add default filetypes, so that we can extend
					-- them in related extras
					filetypes = {
						"javascript",
						"javascriptreact",
						"javascript.jsx",
						"typescript",
						"typescriptreact",
						"typescript.tsx",
						"vue",
					},
					settings = {
						complete_function_calls = true,
						vtsls = {
							enableMoveToFileCodeAction = true,
							autoUseWorkspaceTsdk = true,
							experimental = {
								completion = {
									enableServerSideFuzzyMatch = true,
								},
							},
							tsserver = {
								globalPlugins = {
									{
										name = "@angular/language-server",
										location = require("util.lazy").get_pkg_path(
											"angular-language-server",
											"/node_modules/@angular/language-server"
										),
										enableForWorkspaceTypeScriptVersions = false,
									},
									{
										name = "@vue/typescript-plugin",
										location = require("util.lazy").get_pkg_path(
											"vue-language-server",
											"/node_modules/@vue/language-server"
										),
										languages = { "vue" },
										configNamespace = "typescript",
										enableForWorkspaceTypeScriptVersions = true,
									},
								},
							},
						},
						typescript = {
							updateImportsOnFileMove = { enabled = "always" },
							suggest = {
								completeFunctionCalls = true,
							},
							inlayHints = {
								enumMemberValues = { enabled = true },
								functionLikeReturnTypes = { enabled = true },
								parameterNames = { enabled = "literals" },
								parameterTypes = { enabled = true },
								propertyDeclarationTypes = { enabled = true },
								variableTypes = { enabled = false },
							},
						},
					},
				},
				eslint = {
					settings = {
						workingDirectories = { mode = "auto" },
					},
				},
				biome = {},
				tailwindcss = {
					filetypes_exclude = { "markdown" },
					filetypes_include = {},
				},
				angularls = {},
				volar = {
					init_options = {
						vue = {
							hybridMode = true,
						},
					},
				},
				dockerls = {},
				docker_compose_language_service = {},
				jdtls = {},
				jsonls = {
					-- lazy-load schemastore when needed
					on_new_config = function(new_config)
						new_config.settings.json.schemas = new_config.settings.json.schemas or {}
						vim.list_extend(new_config.settings.json.schemas, require("schemastore").json.schemas())
					end,
					settings = {
						json = {
							format = {
								enable = true,
							},
							validate = { enable = true },
						},
					},
				},
				kotlin_language_server = {},
				omnisharp = {
					handlers = {
						["textDocument/definition"] = function(...)
							return require("omnisharp_extended").handler(...)
						end,
					},
					enable_roslyn_analyzers = true,
					organize_imports_on_format = true,
					enable_import_completion = true,
				},
				ruff = {
					cmd_env = { RUFF_TRACE = "messages" },
					init_options = {
						settings = {
							logLevel = "error",
						},
					},
				},
				basedpyright = {},
				taplo = {
					keys = {
						{
							"K",
							function()
								if vim.fn.expand("%:t") == "Cargo.toml" and require("crates").popup_available() then
									require("crates").show_popup()
								else
									vim.lsp.buf.hover()
								end
							end,
							desc = "Show Crate Documentation",
						},
					},
				},
				texlab = {},
				yamlls = {
					-- Have to add this for yamlls to understand that we support line folding
					capabilities = {
						textDocument = {
							foldingRange = {
								dynamicRegistration = false,
								lineFoldingOnly = true,
							},
						},
					},
					-- lazy-load schemastore when needed
					on_new_config = function(new_config)
						new_config.settings.yaml.schemas = vim.tbl_deep_extend(
							"force",
							new_config.settings.yaml.schemas or {},
							require("schemastore").yaml.schemas()
						)
					end,
					settings = {
						redhat = { telemetry = { enabled = false } },
						yaml = {
							keyOrdering = false,
							format = {
								enable = true,
							},
							validate = true,
							schemaStore = {
								-- Must disable built-in schemaStore support to use
								-- schemas from SchemaStore.nvim plugin
								enable = false,
								-- Avoid TypeError: Cannot read properties of undefined (reading 'length')
								url = "",
							},
						},
					},
				},
			},
			setup = {
				-- stylua: ignore
				vtsls = function(_, opts)
					require("util.lsp").on_attach(function(client, buffer)
						client.commands["_typescript.moveToFileRefactoring"] = function(command)
							local action, uri, range = unpack(command.arguments)

							local function move(newf)
								client.request("workspace/executeCommand", {
									command = command.command,
									arguments = { action, uri, range, newf },
								})
							end

							local fname = vim.uri_to_fname(uri)
							client.request("workspace/executeCommand", {
								command = "typescript.tsserverRequest",
								arguments = {
									"getMoveToRefactoringFileSuggestions",
									{
										file = fname,
										startLine = range.start.line + 1,
										startOffset = range.start.character + 1,
										endLine = range["end"].line + 1,
										endOffset = range["end"].character + 1,
									},
								},
							}, function(_, result)
								local files = result.body.files
								table.insert(files, 1, "Enter new path...")
								vim.ui.select(files, {
									prompt = "Select move destination:",
									format_item = function(f)
										return vim.fn.fnamemodify(f, ":~:.")
									end,
								}, function(f)
									if f and f:find("^Enter new path") then
										vim.ui.input({
											prompt = "Enter move destination:",
											default = vim.fn.fnamemodify(fname, ":h") .. "/",
											completion = "file",
										}, function(newf)
											return newf and move(newf)
										end)
									elseif f then
										move(f)
									end
								end)
							end)
						end
						vim.keymap.set("n", "gD", "<cmd>lua require('util.lsp').execute({ command = 'typescript.goToSourceDefinition', arguments = { vim.lsp.util.make_position_params().textDocument.uri, vim.lsp.util.make_position_params().position }, open = true, })<cr>", { desc = "Goto Source Definition", buffer = buffer, silent = true })
						vim.keymap.set("n", "gR", "<cmd>lua require('util.lsp').execute({ command = 'typescript.findAllFileReferences', arguments = { vim.uri_from_bufnr(0) }, open = true, })<cr>", { desc = "Find References", buffer = buffer, silent = true })
						vim.keymap.set("n", "<leader>co", "<cmd>lua require('util.lsp').action('source.organizeImports')<cr>", { desc = "Organize Imports", buffer = buffer, silent = true })
						vim.keymap.set("n", "<leader>cM", "<cmd>lua require('util.lsp').action('source.addMissingImports.ts')<cr>", { desc = "Add missing imports", buffer = buffer, silent = true })
						vim.keymap.set("n", "<leader>cu", "<cmd>lua require('util.lsp').action('source.removeUnused.ts')<cr>", { desc = "Remove unused imports", buffer = buffer, silent = true })
						vim.keymap.set("n", "<leader>cD", "<cmd>lua require('util.lsp').action('source.fixAll.ts')<cr>", { desc = "Fix all diagnostics", buffer = buffer, silent = true })
						vim.keymap.set("n", "<leader>cV", "<cmd>lua require('util.lsp').execute({ command = 'typescript.selectTypeScriptVersion' })<cr>", { desc = "Select TS workspace version", buffer = buffer, silent = true })
					end, "vtsls")
					-- copy typescript settings to javascript
					opts.settings.javascript =
						vim.tbl_deep_extend("force", {}, opts.settings.typescript, opts.settings.javascript or {})
				end,
				eslint = function()
					vim.api.nvim_create_autocmd("BufWritePre", {
						callback = function(event)
							local client = vim.lsp.get_clients({ bufnr = event.buf, name = "eslint" })[1]
							if client then
								local diag = vim.diagnostic.get(
									event.buf,
									{ namespace = vim.lsp.diagnostic.get_namespace(client.id) }
								)
								if #diag > 0 then
									vim.cmd("EslintFixAll")
								end
							end
						end,
					})
				end,
				tailwindcss = function(_, opts)
					local tw = require("lspconfig.server_configurations.tailwindcss")
					opts.filetypes = opts.filetypes or {}

					-- Add default filetypes
					vim.list_extend(opts.filetypes, tw.default_config.filetypes)

					-- Remove excluded filetypes
					opts.filetypes = vim.tbl_filter(function(ft)
						return not vim.tbl_contains(opts.filetypes_exclude or {}, ft)
					end, opts.filetypes)

					-- Additional settings for Phoenix projects
					opts.settings = {
						tailwindCSS = {
							includeLanguages = {
								elixir = "html-eex",
								eelixir = "html-eex",
								heex = "html-eex",
							},
						},
					}
					vim.list_extend(opts.filetypes, opts.filetypes_include or {})
				end,
				angularls = function()
					require("util.lsp").on_attach(function(client)
						client.server_capabilities.renameProvider = false
					end, "angularls")
				end,
				jdtls = function()
					return true -- avoid duplicate servers
				end,
				-- stylua: ignore
				omnisharp = function()
					require("util.lsp").on_attach(function(_, buffer)
						vim.keymap.set("n", "gd", "<cmd>lua require('omnisharp_extended').telescope_lsp_definitions()<cr>", { desc = "Goto Definition", buffer = buffer, silent = true })
					end, "omnisharp")
				end,
				-- stylua: ignore
				ruff = function()
					require("util.lsp").on_attach(function(client, buffer)
						-- Disable hover in favor of Pyright
						client.server_capabilities.hoverProvider = false
						vim.keymap.set("n", "<leader>co", "<cmd>lua require('util.lsp').action('source.organizeImports')<cr>", { desc = "Organize Imports", buffer = buffer, silent = true })
					end, "ruff")
				end,
				yamlls = function()
					require("util.lsp").on_attach(function(client, _)
						client.server_capabilities.documentFormattingProvider = true
					end, "yamlls")
				end,
			},
		},
		-- stylua: ignore
		config = function(_, opts)
			vim.diagnostic.config(opts.diagnostic)
			require("lspconfig.ui.windows").default_options.border = "rounded"

      require("util.lsp").on_attach(function(client, buffer)
					if client and client.supports_method("textDocument/inlayHint", { bufnr = buffer }) then
						vim.lsp.inlay_hint.enable(true, { bufnr = buffer })
					end

					if client and client.supports_method("textDocument/codeLens", { bufnr = buffer }) then
						vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave" }, {
							buffer = buffer,
							callback = vim.lsp.codelens.refresh,
						})
					end

					vim.keymap.set("n", "<leader>ci", function() if vim.g.float_open then return end vim.g.float_open = true vim.cmd("LspInfo") end, { desc = "Lsp Info", buffer = buffer, silent = true })
					vim.keymap.set("n", "gd", "<cmd>lua require('util.navigation').pick('lsp_definitions', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "Goto Definition", buffer = buffer, silent = true })
					vim.keymap.set("n", "gr", "<cmd>lua require('util.navigation').pick('lsp_references', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "References", buffer = buffer, silent = true })
					vim.keymap.set("n", "gI", "<cmd>lua require('util.navigation').pick('lsp_implementations', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "Goto Implementation", buffer = buffer, silent = true })
					vim.keymap.set("n", "gy", "<cmd>lua require('util.navigation').pick('lsp_typedefs', { jump_to_single_result = true, ignore_current_line = true })<cr>", { desc = "Goto T[y]pe Definition", buffer = buffer, silent = true })
					vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { desc = "Goto Declaration", buffer = buffer, silent = true })
					vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover", buffer = buffer, silent = true })
					vim.keymap.set("n", "gK", vim.lsp.buf.signature_help, { desc = "Signature Help", buffer = buffer, silent = true })
					vim.keymap.set("i", "<c-k>", vim.lsp.buf.signature_help, { desc = "Signature Help", buffer = buffer, silent = true })
					vim.keymap.set({ "n", "x" }, "crr", vim.lsp.buf.code_action, { desc = "Code Action", buffer = buffer, silent = true })
					vim.keymap.set("n", "crn", "<cmd>lua require('live-rename').rename()<cr>", { desc = "Rename", buffer = buffer, silent = true })
					vim.keymap.set({ "n", "x" }, "<leader>cc", vim.lsp.codelens.run, { desc = "Run Codelens", buffer = buffer, silent = true })
					vim.keymap.set("n", "<leader>cC", vim.lsp.codelens.refresh, { desc = "Refresh & Display Codelens", buffer = buffer, silent = true })
				end)

			local capabilities = vim.tbl_deep_extend(
				"force",
				vim.lsp.protocol.make_client_capabilities(),
				require("cmp_nvim_lsp").default_capabilities(),
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

			require("mason-lspconfig").setup({
				ensure_installed = vim.tbl_deep_extend(
          "force",
          ensure_installed,
          require('util.lazy').opts("mason-lspconfig.nvim").ensure_installed or {}
				),
				handlers = { setup },
			})
		end,
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
				"black",
				"prettierd",
				"js-debug-adapter",
				"hadolint",
				"java-debug-adapter",
				"java-test",
				"ktlint",
				"markdown-toc",
				"markdownlint-cli2",
				"csharpier",
				"netcoredbg",
				"codelldb",
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
	-- Json and yaml schema store
	{
		"b0o/SchemaStore.nvim",
		lazy = true,
		version = false,
	},
	-- Better TypeScript errors
	{
		"OlegGulevskyy/better-ts-errors.nvim",
		event = "LazyFile",
	},
	-- Jdtls for Java
	{
		"mfussenegger/nvim-jdtls",
		dependencies = { "folke/which-key.nvim" },
		ft = { "java" },
		opts = function()
			local mason_registry = require("mason-registry")
			local lombok_jar = mason_registry.get_package("jdtls"):get_install_path() .. "/lombok.jar"
			return {
				-- How to find the root dir for a given filename. The default comes from
				-- lspconfig which provides a function specifically for java projects.
				root_dir = require("lspconfig.server_configurations.jdtls").default_config.root_dir,

				-- How to find the project name for a given root dir.
				project_name = function(root_dir)
					return root_dir and vim.fs.basename(root_dir)
				end,

				-- Where are the config and workspace dirs for a project?
				jdtls_config_dir = function(project_name)
					return vim.fn.stdpath("cache") .. "/jdtls/" .. project_name .. "/config"
				end,
				jdtls_workspace_dir = function(project_name)
					return vim.fn.stdpath("cache") .. "/jdtls/" .. project_name .. "/workspace"
				end,

				-- How to run jdtls. This can be overridden to a full java command-line
				-- if the Python wrapper script doesn't suffice.
				cmd = {
					vim.fn.exepath("jdtls"),
					string.format("--jvm-arg=-javaagent:%s", lombok_jar),
				},
				full_cmd = function(opts)
					local fname = vim.api.nvim_buf_get_name(0)
					local root_dir = opts.root_dir(fname)
					local project_name = opts.project_name(root_dir)
					local cmd = vim.deepcopy(opts.cmd)
					if project_name then
						vim.list_extend(cmd, {
							"-configuration",
							opts.jdtls_config_dir(project_name),
							"-data",
							opts.jdtls_workspace_dir(project_name),
						})
					end
					return cmd
				end,
				dap = { hotcodereplace = "auto", config_overrides = {} },
				dap_main = {},
				test = true,
				settings = {
					java = {
						inlayHints = {
							parameterNames = {
								enabled = "all",
							},
						},
					},
				},
			}
		end,
		config = function(_, opts)
			-- Find the extra bundles that should be passed on the jdtls command-line
			local mason_registry = require("mason-registry")
			local bundles = {}
			if opts.dap and mason_registry.is_installed("java-debug-adapter") then
				local java_dbg_pkg = mason_registry.get_package("java-debug-adapter")
				local java_dbg_path = java_dbg_pkg:get_install_path()
				local jar_patterns = {
					java_dbg_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar",
				}
				-- java-test also depends on java-debug-adapter.
				if opts.test and mason_registry.is_installed("java-test") then
					local java_test_pkg = mason_registry.get_package("java-test")
					local java_test_path = java_test_pkg:get_install_path()
					vim.list_extend(jar_patterns, {
						java_test_path .. "/extension/server/*.jar",
					})
				end
				for _, jar_pattern in ipairs(jar_patterns) do
					for _, bundle in ipairs(vim.split(vim.fn.glob(jar_pattern), "\n")) do
						table.insert(bundles, bundle)
					end
				end
			end

			local function attach_jdtls()
				local fname = vim.api.nvim_buf_get_name(0)

				-- Configuration can be augmented and overridden by opts.jdtls
				local config = require("util.lsp").extend_or_override({
					cmd = opts.full_cmd(opts),
					root_dir = opts.root_dir(fname),
					init_options = {
						bundles = bundles,
					},
					settings = opts.settings,
					-- enable CMP capabilities
					capabilities = require("cmp_nvim_lsp").default_capabilities() or nil,
				}, opts.jdtls)

				-- Existing server will be reused if the root_dir matches.
				require("jdtls").start_or_attach(config)
				-- not need to require("jdtls.setup").add_commands(), start automatically adds commands
			end

			-- Attach the jdtls for each java buffer. HOWEVER, this plugin loads
			-- depending on filetype, so this autocmd doesn't run for the first file.
			-- For that, we call directly below.
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "java" },
				callback = attach_jdtls,
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					local client = vim.lsp.get_client_by_id(args.data.client_id)
					if client and client.name == "jdtls" then
						local wk = require("which-key")
						wk.add({
							{
								mode = "n",
								buffer = args.buf,
								{ "<leader>cx", group = "extract" },
								{ "<leader>cxv", require("jdtls").extract_variable_all, desc = "Extract Variable" },
								{ "<leader>cxc", require("jdtls").extract_constant, desc = "Extract Constant" },
								{ "gs", require("jdtls").super_implementation, desc = "Goto Super" },
								{ "gS", require("jdtls.tests").goto_subjects, desc = "Goto Subjects" },
								{ "<leader>co", require("jdtls").organize_imports, desc = "Organize Imports" },
							},
						})
						wk.add({
							{
								mode = "v",
								buffer = args.buf,
								{ "<leader>cx", group = "extract" },
								{
									"<leader>cxm",
									"<esc><cmd>lua require('jdtls').extract_method(true)<cr>",
									desc = "Extract Method",
								},
								{
									"<leader>cxv",
									"<esc><cmd>lua require('jdtls').extract_variable_all(true)<cg>",
									desc = "Extgact Variable",
								},
								{
									"<leader>cxc",
									"<esc><cmd>lua require('jdtls').extract_constant(true)<cr>",
									desc = "Extract Constant",
								},
							},
						})

						if opts.dap and mason_registry.is_installed("java-debug-adapter") then
							-- custom init for Java debugger
							require("jdtls").setup_dap(opts.dap)
							require("jdtls.dap").setup_dap_main_class_configs(opts.dap_main)

							-- Java Test require Java debugger to work
							if opts.test and mason_registry.is_installed("java-test") then
								-- custom keymaps for Java test runner (not yet compatible with neotest)
								wk.add({
									{
										mode = "n",
										buffer = args.buf,
										{ "<leader>t", group = "test" },
										{
											"<leader>tt",
											function()
												require("jdtls.dap").test_class({
													config_overrides = type(opts.test) ~= "boolean"
															and opts.test.config_overrides
														or nil,
												})
											end,
											desc = "Run All Test",
										},
										{
											"<leader>tr",
											function()
												require("jdtls.dap").test_nearest_method({
													config_overrides = type(opts.test) ~= "boolean"
															and opts.test.config_overrides
														or nil,
												})
											end,
											desc = "Run Nearest Test",
										},
										{ "<leader>tT", require("jdtls.dap").pick_test, desc = "Run Test" },
									},
								})
							end
						end
					end
				end,
			})

			-- Avoid race condition by calling attach the first time, since the autocmd won't fire.
			attach_jdtls()
		end,
	},
	-- Better OmniSharp
	{ "Hoffs/omnisharp-extended-lsp.nvim", lazy = true },
	-- Rustacean
	{
		"mrcjkb/rustaceanvim",
		version = "^5", -- Recommended
		ft = { "rust" },
		opts = {
			server = {
				on_attach = function(_, bufnr)
					vim.keymap.set(
						"n",
						"<leader>cR",
						"<cmd>lua vim.cmd.RustLsp('codeAction')<cr>",
						{ desc = "Code Action", buffer = bufnr }
					)
					vim.keymap.set(
						"n",
						"<leader>dr",
						"<cmd>lua vim.cmd.RustLsp('debuggables')<cr>",
						{ desc = "Rust Debuggables", buffer = bufnr }
					)
				end,
				default_settings = {
					-- rust-analyzer language server configuration
					["rust-analyzer"] = {
						server = {
							extraEnv = { ["RUSTUP_TOOLCHAIN"] = "stable" },
						},
						cargo = {
							allFeatures = true,
							loadOutDirsFromCheck = true,
							buildScripts = {
								enable = true,
							},
						},
						-- Add clippy lints for Rust.
						checkOnSave = true,
						procMacro = {
							enable = true,
							ignored = {
								["async-trait"] = { "async_trait" },
								["napi-derive"] = { "napi" },
								["async-recursion"] = { "async_recursion" },
							},
						},
						inlayHints = {
							typeHints = true,
							parameterHints = true,
							maxLength = 25,
							renderColons = true,
							chainingHints = { enable = false },
							bindingModeHints = { enable = false },
							closingBraceHints = { enable = false },
							closureCaptureHints = { enable = false },
							closureReturnTypeHints = { enable = "never" },
							discriminantHints = { enable = "never" },
							expressionAdjustmentHints = { enable = "never" },
							genericParameterHints = {
								const = { enable = false },
								lifetime = { enable = false },
								type = { enable = false },
							},
							implicitDrops = { enable = false },
							lifetimeElisionHints = { enable = "never" },
							rangeExclusiveHints = { enable = false },
							reborrowHints = { enable = "never" },
						},
					},
				},
			},
		},
		config = function(_, opts)
			vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, opts or {})
			if vim.fn.executable("rust-analyzer") == 0 then
				vim.notify(
					"**rust-analyzer** not found in PATH, please install it.\nhttps://rust-analyzer.github.io/",
					vim.log.levels.ERROR,
					{ title = "rustaceanvim" }
				)
			end
		end,
	},
}
