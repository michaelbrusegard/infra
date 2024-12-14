return {
  -- Database client
  {
    'kndndrj/nvim-dbee',
    dependencies = {
      'MunifTanjim/nui.nvim',
    },
    build = function()
      -- Install tries to automatically detect the install method.
      -- if it fails, try calling it with one of these parameters:
      --    "curl", "wget", "bitsadmin", "go"
      require('dbee').install()
    end,
    keys = {
      { '<leader>D', "<cmd>lua require('dbee').toggle()<cr>", desc = 'Database UI' },
    },
    opts = {},
  },
  -- Screenshots
  {
    'michaelrommel/nvim-silicon',
    lazy = true,
    cmd = 'Silicon',
    main = 'nvim-silicon',
    keys = {
      {
        '<leader>ss',
        mode = { 'n', 'x' },
        "<cmd>lua require('nvim-silicon').clip()<cr>",
        desc = 'Take Screenshot',
      },
    },
    opts = {
      disable_defaults = true,
      language = function()
        return vim.bo.filetype
      end,
      window_title = function()
        return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), ':t')
      end,
      to_clipboard = true,
      gobble = true,
      num_separator = ' ',
    },
  },
  -- Markdown
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    build = 'cd app && npm install',
    init = function()
      vim.g.mkdp_filetypes = { 'markdown' }
    end,
    keys = {
      {
        '<leader>cp',
        ft = 'markdown',
        '<cmd>MarkdownPreviewToggle<cr>',
        desc = 'Markdown Preview',
      },
    },
    config = function()
      vim.cmd([[do FileType]])
    end,
  },
  -- Jupyter notebook code running and output viewing
  {
    'benlubas/molten-nvim',
    dependencies = { 'image.nvim' },
    version = '^1.0.0',
    build = ':UpdateRemotePlugins',
    ft = { 'quarto' },
    keys = {
      { '<leader>qr', "<cmd>lua require('quarto.runner').run_above()<cr>", desc = 'Run cell' },
      { '<leader>qR', "<cmd>lua require('quarto.runner').run_all()<cr>", desc = 'Run all cells' },
      { '<leader>ql', "<cmd>lua require('quarto.runner').run_line()<cr>", desc = 'Run line' },
      { '<leader>qi', '<cmd>MoltenInit<cr>', desc = 'Initialize kernel' },
      { '<leader>qI', '<cmd>MoltenInfo<cr>', desc = 'Kernel Info' },
      {
        '<leader>qo',
        '<cmd>noautocmd MoltenEnterOutput<cr>',
        desc = 'Enter output window',
      },
      { '<leader>qm', '<cmd>MoltenImagePopup<cr>', desc = 'Open Image Popup' },
      { '<leader>qh', '<cmd>MoltenHideOutput<cr>', desc = 'Close output window' },
      { '<leader>qv', '<cmd>MoltenEvaluateVisual<cr>', desc = 'Execute visual selection', mode = 'x' },
      { '<leader>qd', '<cmd>MoltenDelete<cr>', desc = 'Delete Molten cell' },
    },
    init = function()
      -- vim.g.molten_auto_image_popup = true
      -- vim.g.molten_auto_open_html_in_browser = true
      vim.g.molten_image_provider = 'image.nvim'
      vim.g.molten_enter_output_behavior = 'open_and_enter'
      vim.g.molten_output_show_exec_time = true
      vim.g.molten_output_win_border = { '', '', '', '' }
      vim.g.molten_output_win_cover_gutter = false
      vim.g.molten_output_win_style = 'minimal'
      -- vim.g.molten_auto_open_output = false
      vim.g.molten_wrap_output = true
      -- vim.g.molten_virt_text_output = true
      vim.g.molten_output_virt_lines = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_output_show_more = true
    end,
  },
  -- Latex
  {
    'lervag/vimtex',
    lazy = false, -- lazy-loading will disable inverse search
    config = function()
      vim.g.vimtex_mappings_disable = { ['n'] = { 'K' } } -- disable `K` as it conflicts with LSP hover
      vim.g.vimtex_quickfix_method = vim.fn.executable('pplatex') == 1 and 'pplatex' or 'latexlog'
    end,
  },
}
