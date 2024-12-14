return {
  {
    'mrjones2014/smart-splits.nvim',
    opts = {},
  },
  { 'saecki/live-rename.nvim', event = 'InsertEnter' },
  {
    'echasnovski/mini.move',
    opts = {
      mappings = {
        left = '<s-h>',
        right = '<s-l>',
        down = '<s-j>',
        up = '<s-k>',
        line_left = '',
        line_right = '',
        line_down = '',
        line_up = '',
      },
      options = {
        reindent_linewise = true,
      },
    },
  },
  {
    'ThePrimeagen/harpoon',
    keys = {
      {
        '<c-h>',
        "<cmd>lua require('harpoon'):list():select(1)<cr>",
        desc = 'Harpoon Quick Menu',
      },
      {
        '<c-j>',
        "<cmd>lua require('harpoon'):list():select(2)<cr>",
        desc = 'Harpoon Quick Menu',
      },
      {
        '<c-k>',
        "<cmd>lua require('harpoon'):list():select(3)<cr>",
        desc = 'Harpoon Quick Menu',
      },
      {
        '<c-l>',
        "<cmd>lua require('harpoon'):list():select(4)<cr>",
        desc = 'Harpoon Quick Menu',
      },
    },
  },
  {
    'stevearc/oil.nvim',
    opts = {},
    keys = {
      {
        '-',
        '<cmd>Oil<cr>',
        desc = 'Open parent directory',
      },
    },
  },
}
