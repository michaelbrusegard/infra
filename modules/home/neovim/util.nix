{pkgs, ...}: {
  programs.nvf.settings.vim = {
    utility.snacks-nvim = {
      enable = true;
      setupOpts = {
        bigfile = {enabled = true;};
        quickfile = {enabled = true;};
        terminal = {
          win = {
            keys = {
              nav_h = {
                __unkeyed-1 = "<C-h>";
                __unkeyed-2 = ''
                  function(self)
                    return self:is_floating() and "<c-h>" or vim.schedule(function()
                      vim.cmd.wincmd("h")
                    end)
                  end
                '';
                desc = "Go to Left Window";
                expr = true;
                mode = "t";
              };
              nav_j = {
                __unkeyed-1 = "<C-j>";
                __unkeyed-2 = ''
                  function(self)
                    return self:is_floating() and "<c-j>" or vim.schedule(function()
                      vim.cmd.wincmd("j")
                    end)
                  end
                '';
                desc = "Go to Lower Window";
                expr = true;
                mode = "t";
              };
              nav_k = {
                __unkeyed-1 = "<C-k>";
                __unkeyed-2 = ''
                  function(self)
                    return self:is_floating() and "<c-k>" or vim.schedule(function()
                      vim.cmd.wincmd("k")
                    end)
                  end
                '';
                desc = "Go to Upper Window";
                expr = true;
                mode = "t";
              };
              nav_l = {
                __unkeyed-1 = "<C-l>";
                __unkeyed-2 = ''
                  function(self)
                    return self:is_floating() and "<c-l>" or vim.schedule(function()
                      vim.cmd.wincmd("l")
                    end)
                  end
                '';
                desc = "Go to Right Window";
                expr = true;
                mode = "t";
              };
            };
          };
        };
      };
    };

    maps.normal = {
      "<leader>." = {
        action = "function() Snacks.scratch() end";
        lua = true;
        desc = "Toggle Scratch Buffer";
      };
      "<leader>S" = {
        action = "function() Snacks.scratch.select() end";
        lua = true;
        desc = "Select Scratch Buffer";
      };
      "<leader>dps" = {
        action = "function() Snacks.profiler.scratch() end";
        lua = true;
        desc = "Profiler Scratch Buffer";
      };
    };
    lazy.plugins = {
      "persistence.nvim" = {
        package = pkgs.vimPlugins.persistence-nvim;
        event = ["BufReadPre"];
        keys = [
          {
            key = "<leader>qs";
            action = "function() require('persistence').load() end";
            lua = true;
            desc = "Restore Session";
          }
          {
            key = "<leader>qS";
            action = "function() require('persistence').select() end";
            lua = true;
            desc = "Select Session";
          }
          {
            key = "<leader>ql";
            action = "function() require('persistence').load({ last = true }) end";
            lua = true;
            desc = "Restore Last Session";
          }
          {
            key = "<leader>qd";
            action = "function() require('persistence').stop() end";
            lua = true;
            desc = "Don't Save Current Session";
          }
        ];
      };

      "plenary.nvim" = {
        package = pkgs.vimPlugins.plenary-nvim;
        lazy = true;
      };
    };
  };
}
