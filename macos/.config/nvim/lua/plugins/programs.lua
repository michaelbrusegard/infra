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
      { '<leader>nr', "<cmd>lua require('quarto.runner').run_above()<cr>", desc = 'Run cell' },
      { '<leader>nR', "<cmd>lua require('quarto.runner').run_all()<cr>", desc = 'Run all cells' },
      { '<leader>nl', "<cmd>lua require('quarto.runner').run_line()<cr>", desc = 'Run line' },
      { '<leader>ni', '<cmd>MoltenInit<cr>', desc = 'Initialize kernel' },
      { '<leader>nI', '<cmd>MoltenInfo<cr>', desc = 'Kernel Info' },
      {
        '<leader>no',
        '<cmd>noautocmd MoltenEnterOutput<cr>',
        desc = 'Enter output window',
      },
      { '<leader>nm', '<cmd>MoltenImagePopup<cr>', desc = 'Open Image Popup' },
      { '<leader>nh', '<cmd>MoltenHideOutput<cr>', desc = 'Close output window' },
      { '<leader>nv', '<cmd>MoltenEvaluateVisual<cr>', desc = 'Execute visual selection', mode = 'x' },
      { '<leader>nd', '<cmd>MoltenDelete<cr>', desc = 'Delete Molten cell' },
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

      -- automatically import output chunks from a jupyter notebook
      vim.api.nvim_create_autocmd('BufAdd', {
        pattern = { '*.ipynb' },
        callback = require('util.programs').imb,
      })

      vim.api.nvim_create_autocmd('BufEnter', {
        pattern = { '*.ipynb' },
        callback = function(event)
          vim.opt_local.conceallevel = 0
          require('quarto').activate()
          if vim.api.nvim_get_vvar('vim_did_enter') ~= 1 then
            require('util.programs').imb(event)
          end
        end,
      })
    end,
  },
  -- Notebook conversion
  {
    'GCBallesteros/jupytext.nvim',
    event = 'LazyFile',
    opts = {
      style = 'quarto',
      output_extension = 'qmd',
      force_ft = 'quarto',
    },
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
