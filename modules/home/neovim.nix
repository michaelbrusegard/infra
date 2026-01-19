{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  neovimConfig = "${config.home.homeDirectory}/Projects/nix-config/config/neovim";
in {
  imports = [inputs.nvf.homeManagerModules.default];

  # Options
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

  # Keymaps
  programs.nvf.settings.vim.keymaps = [
    # better up/down
    {
      mode = ["n" "x"];
      key = "j";
      action = "v:count == 0 ? 'gj' : 'j'";
      options = {
        desc = "Down";
        expr = true;
        silent = true;
      };
    }
    {
      mode = ["n" "x"];
      key = "<Down>";
      action = "v:count == 0 ? 'gj' : 'j'";
      options = {
        desc = "Down";
        expr = true;
        silent = true;
      };
    }
    {
      mode = ["n" "x"];
      key = "k";
      action = "v:count == 0 ? 'gk' : 'k'";
      options = {
        desc = "Up";
        expr = true;
        silent = true;
      };
    }
    {
      mode = ["n" "x"];
      key = "<Up>";
      action = "v:count == 0 ? 'gk' : 'k'";
      options = {
        desc = "Up";
        expr = true;
        silent = true;
      };
    }

    # Move to window using the <ctrl> hjkl keys
    {
      mode = "n";
      key = "<C-h>";
      action = "<C-w>h";
      options = {
        desc = "Go to Left Window";
        remap = true;
      };
    }
    {
      mode = "n";
      key = "<C-j>";
      action = "<C-w>j";
      options = {
        desc = "Go to Lower Window";
        remap = true;
      };
    }
    {
      mode = "n";
      key = "<C-k>";
      action = "<C-w>k";
      options = {
        desc = "Go to Upper Window";
        remap = true;
      };
    }
    {
      mode = "n";
      key = "<C-l>";
      action = "<C-w>l";
      options = {
        desc = "Go to Right Window";
        remap = true;
      };
    }

    # Resize window using <ctrl> arrow keys
    {
      mode = "n";
      key = "<C-Up>";
      action = "<cmd>resize +2<cr>";
      options = {desc = "Increase Window Height";};
    }
    {
      mode = "n";
      key = "<C-Down>";
      action = "<cmd>resize -2<cr>";
      options = {desc = "Decrease Window Height";};
    }
    {
      mode = "n";
      key = "<C-Left>";
      action = "<cmd>vertical resize -2<cr>";
      options = {desc = "Decrease Window Width";};
    }
    {
      mode = "n";
      key = "<C-Right>";
      action = "<cmd>vertical resize +2<cr>";
      options = {desc = "Increase Window Width";};
    }

    # Move Lines
    {
      mode = "n";
      key = "<A-j>";
      action = "<cmd>execute 'move .+' . v:count1<cr>==";
      options = {desc = "Move Down";};
    }
    {
      mode = "n";
      key = "<A-k>";
      action = "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==";
      options = {desc = "Move Up";};
    }
    {
      mode = "i";
      key = "<A-j>";
      action = "<esc><cmd>m .+1<cr>==gi";
      options = {desc = "Move Down";};
    }
    {
      mode = "i";
      key = "<A-k>";
      action = "<esc><cmd>m .-2<cr>==gi";
      options = {desc = "Move Up";};
    }
    {
      mode = "v";
      key = "<A-j>";
      action = ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv";
      options = {desc = "Move Down";};
    }
    {
      mode = "v";
      key = "<A-k>";
      action = ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv";
      options = {desc = "Move Up";};
    }

    # buffers
    {
      mode = "n";
      key = "<S-h>";
      action = "<cmd>bprevious<cr>";
      options = {desc = "Prev Buffer";};
    }
    {
      mode = "n";
      key = "<S-l>";
      action = "<cmd>bnext<cr>";
      options = {desc = "Next Buffer";};
    }
    {
      mode = "n";
      key = "[b";
      action = "<cmd>bprevious<cr>";
      options = {desc = "Prev Buffer";};
    }
    {
      mode = "n";
      key = "]b";
      action = "<cmd>bnext<cr>";
      options = {desc = "Next Buffer";};
    }
    {
      mode = "n";
      key = "<leader>bb";
      action = "<cmd>e #<cr>";
      options = {desc = "Switch to Other Buffer";};
    }
    {
      mode = "n";
      key = "<leader>`";
      action = "<cmd>e #<cr>";
      options = {desc = "Switch to Other Buffer";};
    }
    {
      mode = "n";
      key = "<leader>bD";
      action = "<cmd>bd<cr>";
      options = {desc = "Delete Buffer and Window";};
    }

    # Clear search, diff update and redraw
    {
      mode = "n";
      key = "<leader>ur";
      action = "<Cmd>nohlsearch<Bar>diffupdate<Bar>normal! <C-L><CR>";
      options = {desc = "Redraw / Clear hlsearch / Diff Update";};
    }

    # saner n/N
    {
      mode = "n";
      key = "n";
      action = "'Nn'[v:searchforward].'zv'";
      options = {
        expr = true;
        desc = "Next Search Result";
      };
    }
    {
      mode = "x";
      key = "n";
      action = "'Nn'[v:searchforward]";
      options = {
        expr = true;
        desc = "Next Search Result";
      };
    }
    {
      mode = "o";
      key = "n";
      action = "'Nn'[v:searchforward]";
      options = {
        expr = true;
        desc = "Next Search Result";
      };
    }
    {
      mode = "n";
      key = "N";
      action = "'nN'[v:searchforward].'zv'";
      options = {
        expr = true;
        desc = "Prev Search Result";
      };
    }
    {
      mode = "x";
      key = "N";
      action = "'nN'[v:searchforward]";
      options = {
        expr = true;
        desc = "Prev Search Result";
      };
    }
    {
      mode = "o";
      key = "N";
      action = "'nN'[v:searchforward]";
      options = {
        expr = true;
        desc = "Prev Search Result";
      };
    }

    # Add undo break-points
    {
      mode = "i";
      key = ",";
      action = ",<c-g>u";
    }
    {
      mode = "i";
      key = ".";
      action = ".<c-g>u";
    }
    {
      mode = "i";
      key = ";";
      action = ";<c-g>u";
    }

    # save file
    {
      mode = ["i" "x" "n" "s"];
      key = "<C-s>";
      action = "<cmd>w<cr><esc>";
      options = {desc = "Save File";};
    }

    # keywordprg
    {
      mode = "n";
      key = "<leader>K";
      action = "<cmd>norm! K<cr>";
      options = {desc = "Keywordprg";};
    }

    # better indenting
    {
      mode = "x";
      key = "<";
      action = "<gv";
    }
    {
      mode = "x";
      key = ">";
      action = ">gv";
    }

    # new file
    {
      mode = "n";
      key = "<leader>fn";
      action = "<cmd>enew<cr>";
      options = {desc = "New File";};
    }

    # location list toggle (Lua callback)
    {
      mode = "n";
      key = "<leader>xl";
      options = {desc = "Location List";};
      lua = true;
      action = ''
        local success, err = pcall(
          vim.fn.getloclist(0, { winid = 0 }).winid ~= 0
            and vim.cmd.lclose
            or vim.cmd.lopen
        )
        if not success and err then
          vim.notify(err, vim.log.levels.ERROR)
        end
      '';
    }

    # quickfix list toggle
    {
      mode = "n";
      key = "<leader>xq";
      options = {desc = "Quickfix List";};
      lua = true;
      action = ''
        local success, err = pcall(
          vim.fn.getqflist({ winid = 0 }).winid ~= 0
            and vim.cmd.cclose
            or vim.cmd.copen
        )
        if not success and err then
          vim.notify(err, vim.log.levels.ERROR)
        end
      '';
    }

    {
      mode = "n";
      key = "[q";
      action = "<cmd>cprev<cr>";
      options = {desc = "Previous Quickfix";};
    }
    {
      mode = "n";
      key = "]q";
      action = "<cmd>cnext<cr>";
      options = {desc = "Next Quickfix";};
    }

    # diagnostics
    {
      mode = "n";
      key = "<leader>cd";
      action = "<cmd>lua vim.diagnostic.open_float()<cr>";
      options = {desc = "Line Diagnostics";};
    }
    {
      mode = "n";
      key = "]d";
      action = "<cmd>lua vim.diagnostic.jump({ count =  vim.v.count1, float = true })<cr>";
      options = {desc = "Next Diagnostic";};
    }
    {
      mode = "n";
      key = "[d";
      action = "<cmd>lua vim.diagnostic.jump({ count = -vim.v.count1, float = true })<cr>";
      options = {desc = "Prev Diagnostic";};
    }
    {
      mode = "n";
      key = "]e";
      action = "<cmd>lua vim.diagnostic.jump({ count =  vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true })<cr>";
      options = {desc = "Next Error";};
    }
    {
      mode = "n";
      key = "[e";
      action = "<cmd>lua vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true })<cr>";
      options = {desc = "Prev Error";};
    }
    {
      mode = "n";
      key = "]w";
      action = "<cmd>lua vim.diagnostic.jump({ count =  vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true })<cr>";
      options = {desc = "Next Warning";};
    }
    {
      mode = "n";
      key = "[w";
      action = "<cmd>lua vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true })<cr>";
      options = {desc = "Prev Warning";};
    }

    # windows
    {
      mode = "n";
      key = "<leader>-";
      action = "<C-W>s";
      options = {
        desc = "Split Window Below";
        remap = true;
      };
    }
    {
      mode = "n";
      key = "<leader>|";
      action = "<C-W>v";
      options = {
        desc = "Split Window Right";
        remap = true;
      };
    }
    {
      mode = "n";
      key = "<leader>wd";
      action = "<C-W>c";
      options = {
        desc = "Delete Window";
        remap = true;
      };
    }

    # tabs
    {
      mode = "n";
      key = "<leader><tab>l";
      action = "<cmd>tablast<cr>";
      options = {desc = "Last Tab";};
    }
    {
      mode = "n";
      key = "<leader><tab>o";
      action = "<cmd>tabonly<cr>";
      options = {desc = "Close Other Tabs";};
    }
    {
      mode = "n";
      key = "<leader><tab>f";
      action = "<cmd>tabfirst<cr>";
      options = {desc = "First Tab";};
    }
    {
      mode = "n";
      key = "<leader><tab><tab>";
      action = "<cmd>tabnew<cr>";
      options = {desc = "New Tab";};
    }
    {
      mode = "n";
      key = "<leader><tab>]";
      action = "<cmd>tabnext<cr>";
      options = {desc = "Next Tab";};
    }
    {
      mode = "n";
      key = "<leader><tab>d";
      action = "<cmd>tabclose<cr>";
      options = {desc = "Close Tab";};
    }
    {
      mode = "n";
      key = "<leader><tab>[";
      action = "<cmd>tabprevious<cr>";
      options = {desc = "Previous Tab";};
    }
  ];

  # Clipboard
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

  programs.neovim = {
    enable = true;

    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = true;
    withNodeJs = true;
    withRuby = true;

    extraPackages = with pkgs; [
      lua5_1
      lua51Packages.luarocks
      texliveFull
    ];
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink neovimConfig;
  xdg.configFile."nvim/init.lua".enable = lib.mkForce false;

  home.packages = with pkgs; [
    tree-sitter
  ];
}
