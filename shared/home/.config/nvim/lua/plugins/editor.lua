return {
  { 'nvim-neo-tree/neo-tree.nvim', enabled = false },
  { import = 'lazyvim.plugins.extras.editor.dial' },
  { import = 'lazyvim.plugins.extras.editor.harpoon2' },
  { import = 'lazyvim.plugins.extras.editor.mini-move' },
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
    opts = {
      default_file_explorer = true,
      delete_to_trash = true,
      skip_confirm_for_simple_edits = true,
      view_options = {
        show_hidden = true,
        natural_order = true,
        is_always_hidden = function(name, _)
          return name == '..' or name == '.git' or name == '.DS_Store'
        end,
      },
    },
    keys = {
      {
        '-',
        '<cmd>Oil<cr>',
        desc = 'Open parent directory',
      },
    },
  },
  {
    'mikavilpas/yazi.nvim',
    event = 'VeryLazy',
    keys = {
      {
        '<leader>-',
        '<cmd>Yazi<cr>',
        desc = 'Open yazi at the current file',
      },
      {
        '<leader>cw',
        '<cmd>Yazi cwd<cr>',
        desc = "Open the file manager in nvim's working directory",
      },
    },
    opts = {
      filesystem = {
        hijack_netrw_behavior = true,
      },
      open_for_directories = false,
      keymaps = {
        show_help = '<f1>',
      },
    },
  },
}
