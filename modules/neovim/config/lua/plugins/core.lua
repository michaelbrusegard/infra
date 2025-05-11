return {
  {
    'LazyVim/LazyVim',
    url = 'https://github.com/dpetka2001/LazyVim',
    branch = 'fix/mason-v2',
    version = false,
    opts = {
      colorscheme = 'catppuccin-mocha',
    },
  },
  { 'folke/lazy.nvim', version = false },
  {
    'folke/snacks.nvim',
    opts = {
      dashboard = {
        preset = {
          header = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝]],
        },
      },
      indent = {
        indent = {
          char = '▏',
        },
        scope = {
          underline = true,
          char = '▏',
        },
      },
      picker = {
        sources = {
          files = {
            hidden = true,
          },
          explorer = {
            hidden = true,
            ignored = true,
            exclude = { '.git', '.DS_Store' },
          },
        },
      },
    },
  },
}
