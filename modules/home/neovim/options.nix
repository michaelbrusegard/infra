{pkgs, ...}: {
  programs.nvf.settings.vim = {
    viAlias = false;
    vimAlias = true;
    globals = {
      mapleader = " ";
      maplocalleader = "\\";
      markdown_recommended_style = 0;
    };
    options = {
      autowrite = true;
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

      sessionoptions = [
        "buffers"
        "curdir"
        "tabpages"
        "winsize"
        "help"
        "globals"
        "skiprtp"
        "folds"
      ];

      shiftround = true;
      shiftwidth = 2;
      showmode = false;

      sidescrolloff = 8;
      signcolumn = "yes";

      smartcase = true;
      smartindent = true;

      smoothscroll = true;

      spelllang = ["en"];

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

      fillchars = {
        foldopen = "";
        foldclose = "";
        fold = " ";
        foldsep = " ";
        diff = "╱";
        eob = " ";
      };
    };
  };

  programs.nvf.settings.vim = {
    clipboard = {
      enable = true;
      providers = {
        wl-copy.enable = pkgs.stdenv.hostPlatform.isLinux;
      };
    };
    extraConfigLua = ''
      vim.opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"
    '';
  };
}
