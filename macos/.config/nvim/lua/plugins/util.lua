return {
  -- Library used by other plugins
  { 'nvim-lua/plenary.nvim', lazy = true },
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
