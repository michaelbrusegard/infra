return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      -- virtual text for the debugger
      {
        'theHamsta/nvim-dap-virtual-text',
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
      require('mason-nvim-dap').setup(require('util.lazy').opts('mason-nvim-dap.nvim'))

      vim.api.nvim_set_hl(0, 'DapStoppedLine', { default = true, link = 'Visual' })

      local icons = {
        Stopped = { '󰁕 ', 'DiagnosticWarn', 'DapStoppedLine' },
        Breakpoint = ' ',
        BreakpointCondition = ' ',
        BreakpointRejected = { ' ', 'DiagnosticError' },
        LogPoint = '.>',
      }

      for name, sign in pairs(icons) do
        sign = type(sign) == 'table' and sign or { sign }
        vim.fn.sign_define(
          'Dap' .. name,
          { text = sign[1], texthl = sign[2] or 'DiagnosticInfo', linehl = sign[3], numhl = sign[3] }
        )
      end
    end,
  },
  {
    'jay-babu/mason-nvim-dap.nvim',
    opts = {
      handlers = {
        python = function() end,
      },
    },
  },
  -- Fancy UI for the debugger
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'nvim-neotest/nvim-nio' },
    -- stylua: ignore
    keys = {
      { "<leader>du", function() require("dapui").toggle({ }) end, desc = "Dap UI" },
      { "<leader>de", function() require("dapui").eval() end, desc = "Eval", mode = {"n", "v"} },
    },
    opts = {},
    config = function(_, opts)
      local dap = require('dap')
      local dapui = require('dapui')
      dapui.setup(opts)
      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open {}
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        dapui.close {}
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        dapui.close {}
      end
    end,
  },
  -- Mason.nvim integration
  {
    'jay-babu/mason-nvim-dap.nvim',
    dependencies = 'mason.nvim',
    cmd = { 'DapInstall', 'DapUninstall' },
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
    'nvim-dap',
    dependencies = {
      {
        'jbyuki/one-small-step-for-vimkind',
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
  -- Javascript debugger
  {
    'nvim-dap',
    opts = function()
      local dap = require('dap')
      if not dap.adapters['pwa-node'] then
        require('dap').adapters['pwa-node'] = {
          type = 'server',
          host = 'localhost',
          port = '${port}',
          executable = {
            command = 'node',
            args = {
              require('util.lazy').get_pkg_path('js-debug-adapter', '/js-debug/src/dapDebugServer.js'),
              '${port}',
            },
          },
        }
      end
      if not dap.adapters['node'] then
        dap.adapters['node'] = function(cb, config)
          if config.type == 'node' then
            config.type = 'pwa-node'
          end
          local nativeAdapter = dap.adapters['pwa-node']
          if type(nativeAdapter) == 'function' then
            nativeAdapter(cb, config)
          else
            cb(nativeAdapter)
          end
        end
      end

      local js_filetypes = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }

      local vscode = require('dap.ext.vscode')
      vscode.type_to_filetypes['node'] = js_filetypes
      vscode.type_to_filetypes['pwa-node'] = js_filetypes

      for _, language in ipairs(js_filetypes) do
        if not dap.configurations[language] then
          dap.configurations[language] = {
            {
              type = 'pwa-node',
              request = 'launch',
              name = 'Launch file',
              program = '${file}',
              cwd = '${workspaceFolder}',
            },
            {
              type = 'pwa-node',
              request = 'attach',
              name = 'Attach',
              processId = require('dap.utils').pick_process,
              cwd = '${workspaceFolder}',
            },
          }
        end
      end
    end,
  },
  -- kotlin debugger
  {
    'nvim-dap',
    opts = function()
      local dap = require('dap')
      if not dap.adapters.kotlin then
        dap.adapters.kotlin = {
          type = 'executable',
          command = 'kotlin-debug-adapter',
          options = { auto_continue_if_many_stopped = false },
        }
      end

      dap.configurations.kotlin = {
        {
          type = 'kotlin',
          request = 'launch',
          name = 'This file',
          -- may differ, when in doubt, whatever your project structure may be,
          -- it has to correspond to the class file located at `build/classes/`
          -- and of course you have to build before you debug
          mainClass = function()
            local root = vim.fs.find('src', { path = vim.uv.cwd(), upward = true, stop = vim.env.HOME })[1] or ''
            local fname = vim.api.nvim_buf_get_name(0)
            -- src/main/kotlin/websearch/Main.kt -> websearch.MainKt
            return fname:gsub(root, ''):gsub('main/kotlin/', ''):gsub('.kt', 'Kt'):gsub('/', '.'):sub(2, -1)
          end,
          projectRoot = '${workspaceFolder}',
          jsonLogFile = '',
          enableJsonLogging = false,
        },
        {
          -- Use this for unit tests
          -- First, run
          -- ./gradlew --info cleanTest test --debug-jvm
          -- then attach the debugger to it
          type = 'kotlin',
          request = 'attach',
          name = 'Attach to debugging session',
          port = 5005,
          args = {},
          projectRoot = vim.fn.getcwd,
          hostName = 'localhost',
          timeout = 2000,
        },
      }
    end,
  },
  -- Omnisharp debugger
  {
    'mfussenegger/nvim-dap',
    opts = function()
      local dap = require('dap')
      if not dap.adapters['netcoredbg'] then
        require('dap').adapters['netcoredbg'] = {
          type = 'executable',
          command = vim.fn.exepath('netcoredbg'),
          args = { '--interpreter=vscode' },
          options = {
            detached = false,
          },
        }
      end
      for _, lang in ipairs { 'cs', 'fsharp', 'vb' } do
        if not dap.configurations[lang] then
          dap.configurations[lang] = {
            {
              type = 'netcoredbg',
              name = 'Launch file',
              request = 'launch',
              program = function()
                return vim.fn.input('Path to dll: ', vim.fn.getcwd() .. '/', 'file')
              end,
              cwd = '${workspaceFolder}',
            },
          }
        end
      end
    end,
  },
  -- Python debugger
  {
    'nvim-dap',
    dependencies = {
      'mfussenegger/nvim-dap-python',
      -- stylua: ignore
      keys = {
        { "<leader>dPt", function() require('dap-python').test_method() end, desc = "Debug Method", ft = "python" },
        { "<leader>dPc", function() require('dap-python').test_class() end, desc = "Debug Class", ft = "python" },
      },
      config = function()
        require('dap-python').setup(require('util.lazy').get_pkg_path('debugpy', '/venv/bin/python'))
      end,
    },
  },
}
