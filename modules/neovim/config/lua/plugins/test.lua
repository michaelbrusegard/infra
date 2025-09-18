return {
  { import = 'lazyvim.plugins.extras.test.core' },
  {
    'nvim-neotest/neotest',
    dependencies = { 'nvim-neotest/neotest-python' },
    opts = function(_, opts)
      local django = require('util.django')
      local neotest_python = require('neotest-python')

      opts.adapters = opts.adapters or {}
      table.insert(
        opts.adapters,
        neotest_python({
          runner = 'pytest',
          env = {
            DJANGO_SETTINGS_MODULE = django.get_django_settings(),
          },
          setup_command = { 'bash', '-c', 'DJANGO_SETTINGS_MODULE=' .. django.get_django_settings() .. ' pytest "$@"' },
        })
      )
    end,
  },
}
