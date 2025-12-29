return {
  { import = 'lazyvim.plugins.extras.dap.core' },
  { import = 'lazyvim.plugins.extras.dap.nlua' },
  {
    'mfussenegger/nvim-dap-python',
    config = function()
      local dap_python = require('dap-python')
      dap_python.setup('python')
      dap_python.test_runner = 'pytest'
    end,
  },
  {
    'rcarriga/nvim-dap-ui',
    dependencies = { 'mfussenegger/nvim-dap-python' },
    config = function()
      local dap = require('dap')
      local dapui = require('dapui')
      dapui.setup()
      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open()
      end
    end,
  },
}
