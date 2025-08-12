return {
  { import = 'lazyvim.plugins.extras.formatting.biome' },
  { import = 'lazyvim.plugins.extras.formatting.prettier' },
  {
    'stevearc/conform.nvim',
    opts = {
      formatters = {
        dprint = {
          condition = function(ctx)
            return vim.fs.find({ 'dprint.json' }, { path = ctx.filename, upward = true })[1]
          end,
        },
      },
    },
  },
  {
    'williamboman/mason.nvim',
    opts = { ensure_installed = { 'dprint' } },
  },
}
