return {
  { import = 'lazyvim.plugins.extras.util.dot' },
  { import = 'lazyvim.plugins.extras.util.mini-hipatterns' },
  { import = 'lazyvim.plugins.extras.util.rest' },
  {
    'michaelrommel/nvim-silicon',
    lazy = true,
    cmd = 'Silicon',
    main = 'nvim-silicon',
    keys = {
      {
        '<leader>fs',
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
  {
    'wildfunctions/myeyeshurt',
    opts = {},
    keys = {
      {
        '<leader>ms',
        mode = { 'n' },
        function()
          require('myeyeshurt').start()
        end,
        desc = 'Start snowfall',
      },
      {
        '<leader>mx',
        mode = { 'n' },
        function()
          require('myeyeshurt').stop()
        end,
        desc = 'Stop snowfall',
      },
    },
  },
}
