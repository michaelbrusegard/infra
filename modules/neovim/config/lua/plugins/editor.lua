return {
  { 'nvim-neo-tree/neo-tree.nvim', enabled = false },
  { import = 'lazyvim.plugins.extras.editor.dial' },
  { import = 'lazyvim.plugins.extras.editor.harpoon2' },
  { import = 'lazyvim.plugins.extras.editor.mini-move' },
  { import = 'lazyvim.plugins.extras.editor.navic' },
  { import = 'lazyvim.plugins.extras.editor.overseer' },
  { import = 'lazyvim.plugins.extras.editor.snacks_explorer' },
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
}
