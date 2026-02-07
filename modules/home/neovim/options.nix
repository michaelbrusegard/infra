{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim = {
    viAlias = true;
    vimAlias = true;
    globals = {
      mapleader = " ";
      maplocalleader = "\\";
      markdown_recommended_style = 0;
    };
    options = {
      autowrite = true;
      autoread = true;
      completeopt = "menu,menuone,noselect";
      conceallevel = 2;
      confirm = true;
      cursorline = true;
      expandtab = true;

      foldlevel = 99;
      foldmethod = "indent";
      foldtext = "";

      grepformat = "%f:%l:%c:%m";
      grepprg = "rg --vimgrep";

      ignorecase = true;
      inccommand = "nosplit";
      jumpoptions = "view";
      laststatus = 3;
      linebreak = true;
      list = true;
      mouse = "a";
      number = true;

      pumblend = 10;
      pumheight = 10;

      relativenumber = true;
      ruler = false;
      scrolloff = 4;

      sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds";

      shiftround = true;
      shiftwidth = 2;
      showmode = false;

      shortmess = "filnxtToOFWIc";

      sidescrolloff = 8;
      signcolumn = "yes";

      smartcase = true;
      smartindent = true;

      smoothscroll = true;

      splitbelow = true;
      splitkeep = "screen";
      splitright = true;

      tabstop = 2;
      termguicolors = true;

      timeoutlen = 300;

      undofile = true;
      undolevels = 10000;

      updatetime = 200;
      virtualedit = "block";
      wildmode = "longest:full,full";
      winminwidth = 5;
      wrap = false;

      fillchars = "foldopen:,foldclose:,fold: ,foldsep: ,diff:╱,eob: ";
      shada = "'100,<50,s10,h";
    };

    clipboard = {
      enable = true;
      providers = {
        wl-copy.enable = pkgs.stdenv.isLinux;
      };
    };

    luaConfigRC.options = ''
      vim.opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"

      vim.filetype.add({
        extension = {
          http = "http",
          gs = 'javascript',
        },
      })

      vim.g.loaded_gzip = 1
      vim.g.loaded_zip = 1
      vim.g.loaded_zipPlugin = 1
      vim.g.loaded_tar = 1
      vim.g.loaded_tarPlugin = 1
      vim.g.loaded_getscript = 1
      vim.g.loaded_getscriptPlugin = 1
      vim.g.loaded_vimball = 1
      vim.g.loaded_vimballPlugin = 1
      vim.g.loaded_2html_plugin = 1
      vim.g.loaded_matchit = 1
      vim.g.loaded_matchparen = 1
      vim.g.loaded_logiPat = 1
      vim.g.loaded_rrhelper = 1
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
      vim.g.loaded_netrwSettings = 1
      vim.g.loaded_netrwFileHandlers = 1
    '';

    spellcheck = {
      enable = true;
      languages = ["en"];
    };
  };
}
