_: {
  programs.neovim.spec.keymaps = [
    # Better up/down
    {
      key = "j";
      mode = ["n" "x"];
      desc = "Down";
      action = "v:count == 0 ? 'gj' : 'j'";
      expr = true;
    }
    {
      key = "<Down>";
      mode = ["n" "x"];
      desc = "Down";
      action = "v:count == 0 ? 'gj' : 'j'";
      expr = true;
    }
    {
      key = "k";
      mode = ["n" "x"];
      desc = "Up";
      action = "v:count == 0 ? 'gk' : 'k'";
      expr = true;
    }
    {
      key = "<Up>";
      mode = ["n" "x"];
      desc = "Up";
      action = "v:count == 0 ? 'gk' : 'k'";
      expr = true;
    }

    # Move to window using the <ctrl> hjkl keys
    {
      key = "<C-h>";
      mode = "n";
      desc = "Move to left window";
      action = "<C-w>h";
    }
    {
      key = "<C-j>";
      mode = "n";
      desc = "Move to bottom window";
      action = "<C-w>j";
    }
    {
      key = "<C-k>";
      mode = "n";
      desc = "Move to top window";
      action = "<C-w>k";
    }
    {
      key = "<C-l>";
      mode = "n";
      desc = "Move to right window";
      action = "<C-w>l";
    }

    # Resize window using <ctrl> arrow keys
    {
      key = "<C-Up>";
      mode = "n";
      desc = "Increase window height";
      action = "<C-w>+";
    }
    {
      key = "<C-Down>";
      mode = "n";
      desc = "Decrease window height";
      action = "<C-w>-";
    }
    {
      key = "<C-Left>";
      mode = "n";
      desc = "Decrease window width";
      action = "<C-w><";
    }
    {
      key = "<C-Right>";
      mode = "n";
      desc = "Increase window width";
      action = "<C-w>>";
    }

    # Buffers
    {
      key = "[b";
      mode = "n";
      desc = "Prev Buffer";
      action = "<cmd>bprevious<cr>";
    }
    {
      key = "]b";
      mode = "n";
      desc = "Next Buffer";
      action = "<cmd>bnext<cr>";
    }
    {
      key = "<leader>bb";
      mode = "n";
      desc = "Switch to Other Buffer";
      action = "<cmd>e #<cr>";
    }
    {
      key = "<leader>`";
      mode = "n";
      desc = "Switch to Other Buffer";
      action = "<cmd>e #<cr>";
    }
    {
      key = "<leader>bD";
      mode = "n";
      desc = "Delete Buffer and Window";
      action = "<cmd>:bd<cr>";
    }

    # Search and Navigation (Misc)
    {
      key = "<esc>";
      mode = ["i" "n" "s"];
      desc = "Escape and Clear hlsearch";
      action = "<cmd>noh<cr><esc>";
    }
    {
      key = "<leader>ur";
      mode = "n";
      desc = "Redraw / Clear hlsearch / Diff Update";
      action = "<Cmd>nohlsearch<Bar>diffupdate<Bar>normal! <C-L><CR>";
    }
    {
      key = "n";
      mode = "n";
      desc = "Next Search Result";
      action = "'Nn'[v:searchforward].'zv'";
      expr = true;
    }
    {
      key = "n";
      mode = "x";
      desc = "Next Search Result";
      action = "'Nn'[v:searchforward]";
      expr = true;
    }
    {
      key = "n";
      mode = "o";
      desc = "Next Search Result";
      action = "'Nn'[v:searchforward]";
      expr = true;
    }
    {
      key = "N";
      mode = "n";
      desc = "Prev Search Result";
      action = "'nN'[v:searchforward].'zv'";
      expr = true;
    }
    {
      key = "N";
      mode = "x";
      desc = "Prev Search Result";
      action = "'nN'[v:searchforward]";
      expr = true;
    }
    {
      key = "N";
      mode = "o";
      desc = "Prev Search Result";
      action = "'nN'[v:searchforward]";
      expr = true;
    }

    # Better indenting
    {
      key = "<";
      mode = "x";
      action = "<gv";
    }
    {
      key = ">";
      mode = "x";
      action = ">gv";
    }

    # Commenting
    {
      key = "gco";
      mode = "n";
      desc = "Add Comment Below";
      action = "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
    }
    {
      key = "gcO";
      mode = "n";
      desc = "Add Comment Above";
      action = "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
    }

    # New file
    {
      key = "<leader>fn";
      mode = "n";
      desc = "New File";
      action = "<cmd>enew<cr>";
    }

    # Split window
    {
      key = "<leader>-";
      mode = "n";
      desc = "Split Window Below";
      action = "<C-w>s";
    }
    {
      key = "<leader>|";
      mode = "n";
      desc = "Split Window Right";
      action = "<C-w>v";
    }
    {
      key = "<leader>wd";
      mode = "n";
      desc = "Delete Window";
      action = "<C-w>c";
    }

    # Diagnostics
    {
      key = "<leader>cd";
      mode = "n";
      desc = "Line Diagnostics";
      action = "vim.diagnostic.open_float";
      lua = true;
    }
    {
      key = "]d";
      mode = "n";
      desc = "Next Diagnostic";
      action = "function() vim.diagnostic.jump({ count = vim.v.count1, float = true }) end";
      lua = true;
    }
    {
      key = "[d";
      mode = "n";
      desc = "Prev Diagnostic";
      action = "function() vim.diagnostic.jump({ count = -vim.v.count1, float = true }) end";
      lua = true;
    }
    {
      key = "]e";
      mode = "n";
      desc = "Next Error";
      action = "function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end";
      lua = true;
    }
    {
      key = "[e";
      mode = "n";
      desc = "Prev Error";
      action = "function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end";
      lua = true;
    }
    {
      key = "]w";
      mode = "n";
      desc = "Next Warning";
      action = "function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end";
      lua = true;
    }
    {
      key = "[w";
      mode = "n";
      desc = "Prev Warning";
      action = "function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end";
      lua = true;
    }
  ];
}
