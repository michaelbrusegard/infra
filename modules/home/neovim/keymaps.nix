_: {
  programs.nvf.settings.vim.keymaps = [
    # Better up/down
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

    # Buffers
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
      key = "<leader>bd";
      action = "function() require('snacks').bufdelete() end";
      lua = true;
      options = {desc = "Delete Buffer";};
    }
    {
      mode = "n";
      key = "<leader>bo";
      action = "function() require('snacks').bufdelete.other() end";
      lua = true;
      options = {desc = "Delete Other Buffers";};
    }
    {
      mode = "n";
      key = "<leader>bD";
      action = "<cmd>bd<cr>";
      options = {desc = "Delete Buffer and Window";};
    }

    # Search and Navigation
    {
      mode = ["i" "n" "s"];
      key = "<esc>";
      action = ''
        function()
          vim.cmd("noh")
          return "<esc>"
        end
      '';
      lua = true;
      options = {
        expr = true;
        desc = "Escape and Clear hlsearch";
      };
    }
    {
      mode = "n";
      key = "<leader>ur";
      action = "<Cmd>nohlsearch<Bar>diffupdate<Bar>normal! <C-L><CR>";
      options = {desc = "Redraw / Clear hlsearch / Diff Update";};
    }
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

    # Better indenting
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

    # Commenting
    {
      mode = "n";
      key = "gco";
      action = "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
      options = {desc = "Add Comment Below";};
    }
    {
      mode = "n";
      key = "gcO";
      action = "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
      options = {desc = "Add Comment Above";};
    }

    # Toggles (using Snacks)
    {
      mode = "n";
      key = "<leader>uf";
      action = "function() vim.g.autoformat = not (vim.g.autoformat == nil or vim.g.autoformat); require('snacks').notify.info('Autoformat ' .. (vim.g.autoformat and 'Enabled' or 'Disabled')) end";
      lua = true;
      options = {desc = "Toggle Auto Format (Global)";};
    }
    {
      mode = "n";
      key = "<leader>uF";
      action = "function() vim.b.autoformat = not (vim.b.autoformat == nil or vim.b.autoformat); require('snacks').notify.info('Autoformat (buffer) ' .. (vim.b.autoformat and 'Enabled' or 'Disabled')) end";
      lua = true;
      options = {desc = "Toggle Auto Format (Buffer)";};
    }
    {
      mode = "n";
      key = "<leader>us";
      action = "function() require('snacks').toggle.option('spell', { name = 'Spelling' }):toggle() end";
      lua = true;
      options = {desc = "Toggle Spelling";};
    }
    {
      mode = "n";
      key = "<leader>uw";
      action = "function() require('snacks').toggle.option('wrap', { name = 'Wrap' }):toggle() end";
      lua = true;
      options = {desc = "Toggle Wrap";};
    }
    {
      mode = "n";
      key = "<leader>uL";
      action = "function() require('snacks').toggle.option('relativenumber', { name = 'Relative Number' }):toggle() end";
      lua = true;
      options = {desc = "Toggle Relative Number";};
    }
    {
      mode = "n";
      key = "<leader>ud";
      action = "function() require('snacks').toggle.diagnostics():toggle() end";
      lua = true;
      options = {desc = "Toggle Diagnostics";};
    }
    {
      mode = "n";
      key = "<leader>ul";
      action = "function() require('snacks').toggle.line_number():toggle() end";
      lua = true;
      options = {desc = "Toggle Line Number";};
    }
    {
      mode = "n";
      key = "<leader>uc";
      action = "function() require('snacks').toggle.option('conceallevel', { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2, name = 'Conceal Level' }):toggle() end";
      lua = true;
      options = {desc = "Toggle Conceal Level";};
    }
    {
      mode = "n";
      key = "<leader>uT";
      action = "function() require('snacks').toggle.treesitter():toggle() end";
      lua = true;
      options = {desc = "Toggle Treesitter";};
    }
    {
      mode = "n";
      key = "<leader>ub";
      action = "function() require('snacks').toggle.option('background', { off = 'light', on = 'dark' , name = 'Dark Background' }):toggle() end";
      lua = true;
      options = {desc = "Toggle Dark Background";};
    }
    {
      mode = "n";
      key = "<leader>uD";
      action = "function() require('snacks').toggle.dim():toggle() end";
      lua = true;
      options = {desc = "Toggle Dim";};
    }
    {
      mode = "n";
      key = "<leader>ua";
      action = "function() require('snacks').toggle.animate():toggle() end";
      lua = true;
      options = {desc = "Toggle Animate";};
    }
    {
      mode = "n";
      key = "<leader>ug";
      action = "function() require('snacks').toggle.indent():toggle() end";
      lua = true;
      options = {desc = "Toggle Indent Guides";};
    }
    {
      mode = "n";
      key = "<leader>uS";
      action = "function() require('snacks').toggle.scroll():toggle() end";
      lua = true;
      options = {desc = "Toggle Scroll";};
    }
    {
      mode = "n";
      key = "<leader>uh";
      action = "function() if vim.lsp.inlay_hint then require('snacks').toggle.inlay_hints():toggle() end end";
      lua = true;
      options = {desc = "Toggle Inlay Hints";};
    }

    # Git (using Snacks)
    {
      mode = "n";
      key = "<leader>gg";
      action = "function() require('snacks').lazygit() end";
      lua = true;
      options = {desc = "Lazygit (cwd)";};
    }
    {
      mode = "n";
      key = "<leader>gB";
      action = "function() require('snacks').gitbrowse() end";
      lua = true;
      options = {desc = "Git Browse (open)";};
    }
    {
      mode = ["n" "x"];
      key = "<leader>gY";
      action = "function() require('snacks').gitbrowse({ open = function(url) vim.fn.setreg('+', url) end, notify = false }) end";
      lua = true;
      options = {desc = "Git Browse (copy)";};
    }

    # UI / Windows
    {
      mode = "n";
      key = "<leader>wm";
      action = "function() require('snacks').toggle.zoom():toggle() end";
      lua = true;
      options = {desc = "Toggle Zoom";};
    }
    {
      mode = "n";
      key = "<leader>uz";
      action = "function() require('snacks').toggle.zen():toggle() end";
      lua = true;
      options = {desc = "Toggle Zen Mode";};
    }
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

    # Tabs
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

    # System / Misc
    {
      mode = "n";
      key = "<leader>l";
      action = "<cmd>Lazy<cr>";
      options = {desc = "Lazy";};
    }
    {
      mode = "n";
      key = "<leader>qq";
      action = "<cmd>qa<cr>";
      options = {desc = "Quit All";};
    }
    {
      mode = ["n" "x"];
      key = "<localleader>r";
      action = "function() require('snacks').debug.run() end";
      lua = true;
      options = {desc = "Run Lua";};
    }
    {
      mode = "n";
      key = "<leader>fn";
      action = "<cmd>enew<cr>";
      options = {desc = "New File";};
    }
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
    {
      mode = ["i" "x" "n" "s"];
      key = "<C-s>";
      action = "<cmd>w<cr><esc>";
      options = {desc = "Save File";};
    }
    {
      mode = "n";
      key = "<leader>K";
      action = "<cmd>norm! K<cr>";
      options = {desc = "Keywordprg";};
    }

    # Formatting and Diagnostics
    {
      mode = ["n" "x"];
      key = "<leader>cf";
      action = "function() require('conform').format({ bufnr = 0 }) end";
      lua = true;
      options = {desc = "Format";};
    }
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
  ];
}
