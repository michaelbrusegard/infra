return {
  {
    'LazyVim/LazyVim',
    version = false,
    opts = {
      colorscheme = 'rose-pine',
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
        },
      },
    },
  },
}
