return {
  { import = 'lazyvim.plugins.extras.ai.copilot' },
  { import = 'lazyvim.plugins.extras.ai.supermaven' },
  {
    'olimorris/codecompanion.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    keys = {
      { '<leader>a', '', desc = '+ai', mode = { 'n', 'v' } },
      {
        '<leader>aa',
        function()
          return require('codecompanion').toggle()
        end,
        desc = 'Toggle Chat',
        mode = { 'n', 'v' },
      },
      {
        '<leader>aq',
        function()
          local input = vim.fn.input('Quick Chat: ')
          if input ~= '' then
            local mode = vim.fn.mode()
            if mode == 'v' or mode == 'V' then
              local start_pos = vim.fn.getpos("'<")
              local end_pos = vim.fn.getpos("'>")
              local lines = vim.api.nvim_buf_get_text(0, start_pos[2] - 1, 0, end_pos[2] - 1, -1, {})
              local selected_text = table.concat(lines, '\n')
              vim.cmd('CodeCompanion ' .. selected_text .. ' ' .. input)
            else
              vim.cmd('CodeCompanion ' .. input)
            end
          end
        end,
        desc = 'Quick Chat',
        mode = { 'n', 'v' },
      },
      {
        '<leader>ap',
        '<cmd>CodeCompanionActions<cr>',
        desc = 'Prompt Actions',
        mode = { 'n', 'v' },
      },
    },
    opts = {
      strategies = {
        chat = {
          adapter = 'copilot_claude',
        },
      },
      adapters = {
        copilot_claude = function()
          return require('codecompanion.adapters').extend(
            'copilot',
            { schema = { model = { default = 'claude-3.5-sonnet' } } }
          )
        end,
      },
      display = {
        chat = {
          intro_message = '',
        },
      },
    },
  },
}
