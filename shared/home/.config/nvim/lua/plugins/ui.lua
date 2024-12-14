return {
  {
    'nvim-lualine/lualine.nvim',
    opts = {
      options = {
        section_separators = { left = '', right = '' },
        component_separators = { left = '', right = '' },
      },
      sections = {
        lualine_a = { { 'mode', fmt = string.lower } },
        lualine_b = { 'branch' },
        lualine_y = { 'progress' },
        lualine_z = { 'location' },
      },
      extensions = { 'lazy', 'mason', 'fzf' },
    },
  },
}
