{lib, ...}: {
  programs.neovim = {
    spec = {
      globals = {
        mapleader = " ";
        maplocalleader = "\\";
        markdown_recommended_style = 0;

        loaded_gzip = 1;
        loaded_zip = 1;
        loaded_zipPlugin = 1;
        loaded_tar = 1;
        loaded_tarPlugin = 1;
        loaded_getscript = 1;
        loaded_getscriptPlugin = 1;
        loaded_vimball = 1;
        loaded_vimballPlugin = 1;
        loaded_2html_plugin = 1;
        loaded_matchit = 1;
        loaded_matchparen = 1;
        loaded_logiPat = 1;
        loaded_rrhelper = 1;
        loaded_netrw = 1;
        loaded_netrwPlugin = 1;
        loaded_netrwSettings = 1;
        loaded_netrwFileHandlers = 1;
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
        foldtext = "";
        foldmethod = "indent";

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

        spelllang = "en,nb";
        spelloptions = "camel";

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

      filetypes.extensions = {
        http = "http";
        gs = "javascript";
      };
    };
    extraLuaConfig = lib.mkOrder 100 ''
      if vim.env.SSH_CONNECTION then
        vim.opt.clipboard = ""
      else
        vim.opt.clipboard = "unnamedplus"
      end
    '';
  };
}
