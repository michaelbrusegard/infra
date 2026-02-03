{pkgs, ...}: {
  programs.nvf.settings.vim = {
    utility.snacks-nvim = {
      enable = true;
      setupOpts = {
        bigfile = {enabled = true;};
        explorer = {enabled = true;};
        image = {enabled = true;};
        indent = {
          enabled = true;
          indent = {char = "▏";};
          scope = {
            underline = true;
            char = "▏";
          };
        };
        input = {enabled = true;};
        notifier = {enabled = true;};
        picker = {
          enabled = true;
          sources = {
            files = {hidden = true;};
            explorer = {
              hidden = true;
              ignored = true;
              exclude = [".git" ".DS_Store" "node_modules" ".next" ".cache" "target" "dist" "build"];
            };
          };
        };
        quickfile = {enabled = true;};
        scope = {enabled = true;};
        scroll = {enabled = true;};
        statuscolumn = {enabled = false;};
        words = {enabled = true;};
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

    # Ensure Snacks is available for keymaps
    # Removed global initialization as per user request

    maps.normal = {
      "<leader>." = {
        action = "function() require('snacks').scratch() end";
        lua = true;
        desc = "Toggle Scratch Buffer";
      };
      "<leader>S" = {
        action = "function() require('snacks').scratch.select() end";
        lua = true;
        desc = "Select Scratch Buffer";
      };
      "<leader>dps" = {
        action = "function() require('snacks').profiler.scratch() end";
        lua = true;
        desc = "Profiler Scratch Buffer";
      };
      "<leader>n" = {
        action = "function() require('snacks').picker.notifications() end";
        lua = true;
        desc = "Notification History";
      };
      "<leader>un" = {
        action = "function() require('snacks').notifier.hide() end";
        lua = true;
        desc = "Dismiss All Notifications";
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
