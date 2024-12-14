return {
  -- Library used by other plugins
  { 'nvim-lua/plenary.nvim', lazy = true },
  -- Image support
  {
    '3rd/image.nvim',
    dependencies = { 'leafo/magick' },
    event = 'LazyFile',
    opts = {
      backend = 'kitty',
      integrations = {
        markdown = {
          enabled = false,
          clear_in_insert_mode = true,
          download_remote_images = true,
          only_render_image_at_cursor = true,
          filetypes = { 'markdown', 'quarto' },
        },
        html = {
          enabled = false,
        },
        css = {
          enabled = false,
        },
      },
      max_height_window_percentage = 100,
      max_width_window_percentage = 100,
      window_overlap_clear_enabled = true,
      editor_only_render_when_focused = false,
      -- hijack_file_patterns = { '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif' },
    },
  },
  -- Learn the best way to do vim commands
  {
    'm4xshen/hardtime.nvim',
    event = 'LazyFile',
    opts = {},
  },
  -- Eye strain prevention
  {
    'wildfunctions/myeyeshurt',
    event = 'VeryLazy',
    keys = {
      {
        '<leader>ms',
        "<cmd>lua require('myeyeshurt').start()<cr>",
        desc = 'Trigger flakes',
      },
      {
        '<leader>mx',
        "<cmd>lua require('myeyeshurt').stop()<cr>",
        desc = 'Stop flakes',
      },
    },
    opts = {
      initialFlakes = 1,
      flakeOdds = 20,
      maxFlakes = 750,
      nextFrameDelay = 175,
      useDefaultKeymaps = false,
      flake = { '*', '.' },
      minutesUntilRest = 20,
    },
  },
}
