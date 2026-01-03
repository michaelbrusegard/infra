local sql_ft = { 'sql', 'mysql', 'plsql' }
return {
  { import = 'lazyvim.plugins.extras.lang.cmake' },
  { import = 'lazyvim.plugins.extras.lang.docker' },
  { import = 'lazyvim.plugins.extras.lang.git' },
  { import = 'lazyvim.plugins.extras.lang.go' },
  { import = 'lazyvim.plugins.extras.lang.java' },
  { import = 'lazyvim.plugins.extras.lang.json' },
  { import = 'lazyvim.plugins.extras.lang.kotlin' },
  { import = 'lazyvim.plugins.extras.lang.markdown' },
  { import = 'lazyvim.plugins.extras.lang.nix' },
  { import = 'lazyvim.plugins.extras.lang.rust' },
  { import = 'lazyvim.plugins.extras.lang.tailwind' },
  { import = 'lazyvim.plugins.extras.lang.tex' },
  { import = 'lazyvim.plugins.extras.lang.toml' },
  { import = 'lazyvim.plugins.extras.lang.typescript' },
  -- Python
  { import = 'lazyvim.plugins.extras.lang.python' },
  {
    'benomahony/uv.nvim',
    ft = { 'python' },
    opts = {
      picker_integration = true,
      keymaps = {
        prefix = '<leader>cu',
      },
    },
  },
  -- SQL
  recommended = function()
    return LazyVim.extras.wants({
      ft = sql_ft,
    })
  end,
  {
    'kndndrj/nvim-dbee',
    dependencies = {
      'MunifTanjim/nui.nvim',
    },
    build = function()
      require('dbee').install()
    end,
    keys = {
      {
        '<leader>D',
        function()
          require('dbee').toggle()
        end,
        desc = 'Toggle DBee',
      },
    },
    opts = {},
  },
  {
    'nvim-treesitter/nvim-treesitter',
    optional = true,
    opts = { ensure_installed = { 'sql' } },
  },
  {
    'mason-org/mason.nvim',
    opts = { ensure_installed = { 'sqlfluff' } },
  },
  {
    'stevearc/conform.nvim',
    opts = function(_, opts)
      opts.formatters.sqlfluff = {
        args = { 'format', '--dialect=ansi', '-' },
      }
      for _, ft in ipairs(sql_ft) do
        opts.formatters_by_ft[ft] = opts.formatters_by_ft[ft] or {}
        table.insert(opts.formatters_by_ft[ft], 'sqlfluff')
      end
    end,
  },
  -- Nix
  {
    'mason-org/mason.nvim',
    opts = { ensure_installed = { 'alejandra' } },
  },
  {
    'stevearc/conform.nvim',
    opts = {
      formatters_by_ft = {
        nix = { 'alejandra' },
      },
    },
  },
}
