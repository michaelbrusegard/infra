return {
  -- Copilot
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    build = ':Copilot auth',
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        help = true,
      },
    },
  },
  -- Copilot chat
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    branch = 'canary',
    cmd = 'CopilotChat',
    opts = function()
      local select = require('CopilotChat.select')
      return {
        model = 'gpt-4',
        auto_insert_mode = true,
        auto_follow_cursor = false,
        show_help = false,
        question_header = '',
        answer_header = '',
        window = {
          width = 0.4,
        },
        mappings = {
          complete = {
            insert = '',
          },
        },
        selection = function(source)
          return select.visual(source)
        end,
        prompts = {
          Review = {
            prompt = '/COPILOT_REVIEW Review the selected code.',
            callback = function(response, source)
              local ns = vim.api.nvim_create_namespace('copilot_review')
              local diagnostics = {}
              for line in response:gmatch('[^\r\n]+') do
                if line:find('^line=') then
                  local start_line = nil
                  local end_line = nil
                  local message = nil
                  local single_match, message_match = line:match('^line=(%d+): (.*)$')
                  if not single_match then
                    local start_match, end_match, m_message_match = line:match('^line=(%d+)-(%d+): (.*)$')
                    if start_match and end_match then
                      start_line = tonumber(start_match)
                      end_line = tonumber(end_match)
                      message = m_message_match
                    end
                  else
                    start_line = tonumber(single_match)
                    end_line = start_line
                    message = message_match
                  end

                  if start_line and end_line then
                    table.insert(diagnostics, {
                      lnum = start_line - 1,
                      end_lnum = end_line - 1,
                      col = 0,
                      message = message,
                      severity = vim.diagnostic.severity.WARN,
                      source = 'Copilot Review',
                    })
                  end
                end
              end
              vim.diagnostic.set(ns, source.bufnr, diagnostics)
            end,
          },
          Explain = {
            prompt = '/COPILOT_EXPLAIN Write an explanation for the active selection as paragraphs of text.',
          },
          Optimize = {
            prompt = '/COPILOT_GENERATE Optimize the selected code to improve performance and readablilty.',
          },
          Tests = {
            prompt = '/COPILOT_GENERATE Please generate tests for my code.',
          },
          FixDiagnostic = {
            prompt = 'Please assist with the following diagnostic issue in file:',
            selection = select.diagnostics,
          },
          Heading = {
            prompt = 'Please provide a single-line comment heading for the selected code. Only return the heading.',
          },
          BetterNamings = {
            prompt = 'Please provide better names for the following variables and functions.',
          },
        },
      }
    end,
    keys = {
      { '<c-s>', '<cr>', ft = 'copilot-chat', desc = 'Submit Prompt', remap = true },
      { '<leader>a', '', desc = '+ai', mode = { 'n', 'v' } },
      {
        '<leader>aa',
        function()
          return require('CopilotChat').toggle()
        end,
        desc = 'Toggle',
        mode = { 'n', 'v' },
      },
      { '<leader>ae', '<cmd>CopilotChatExplain<cr>', desc = 'Explain code', mode = { 'n', 'v' } },
      { '<leader>at', '<cmd>CopilotChatTests<cr>', desc = 'Generate tests', mode = { 'n', 'v' } },
      { '<leader>ar', '<cmd>CopilotChatReview<cr>', desc = 'Review code', mode = { 'n', 'v' } },
      { '<leader>ao', '<cmd>CopilotChatOptimize<cr>', desc = 'Optimize code', mode = { 'n', 'v' } },
      { '<leader>ad', '<cmd>CopilotChatFixDiagnostic<cr>', desc = 'Diagnostics', mode = { 'n', 'v' } },
      { '<leader>ah', '<cmd>CopilotChatHeading<cr>', desc = 'Suggest Heading', mode = { 'n', 'v' } },
      { '<leader>an', '<cmd>CopilotChatBetterNamings<cr>', desc = 'Better Naming', mode = { 'n', 'v' } },
      {
        '<leader>aq',
        function()
          local input = vim.fn.input('Quick Chat: ')
          if input ~= '' then
            require('CopilotChat').ask(input)
          end
        end,
        desc = 'Quick Chat',
        mode = { 'n', 'v' },
      },
      -- Show prompts actions with fzf
      {
        '<leader>ap',
        require('util.coding').copilot_pick('prompt'),
        desc = 'Prompt Actions Ai',
        mode = { 'n', 'v' },
      },
    },
    config = function(_, opts)
      local chat = require('CopilotChat')
      require('CopilotChat.integrations.cmp').setup()

      vim.api.nvim_create_autocmd('BufEnter', {
        pattern = 'copilot-chat',
        callback = function()
          vim.opt_local.signcolumn = 'no'
          vim.keymap.set('n', '<C-s>', '<cmd>CopilotChatStop<cr>', { buffer = true })
        end,
      })

      chat.setup(opts)
    end,
  },
}
