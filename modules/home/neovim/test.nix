{pkgs, ...}: {
  programs.nvf.settings.vim = {
    lazy.plugins = {
      "neotest" = {
        package = pkgs.vimPlugins.neotest;
        setupModule = "neotest";
        setupOpts = {
          status = {virtual_text = true;};
          output = {open_on_run = true;};
          quickfix = {
            open = ''
              function()
                if require("trouble").is_open() then
                  require("trouble").open({ mode = "quickfix", focus = false })
                else
                  vim.cmd("copen")
                end
              end
            '';
          };
        };
        after = ''
          local neotest_ns = vim.api.nvim_create_namespace("neotest")
          vim.diagnostic.config({
            virtual_text = {
              format = function(diagnostic)
                local message = diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
                return message
              end,
            },
          }, neotest_ns)
        '';
      };

      "nvim-nio" = {
        package = pkgs.vimPlugins.nvim-nio;
        lazy = true;
      };
    };

    keymaps = [
      {
        mode = "n";
        key = "<leader>ta";
        action = "function() require('neotest').run.attach() end";
        lua = true;
        options = {desc = "Attach to Test (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tt";
        action = "function() require('neotest').run.run(vim.fn.expand('%')) end";
        lua = true;
        options = {desc = "Run File (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tT";
        action = "function() require('neotest').run.run(vim.uv.cwd()) end";
        lua = true;
        options = {desc = "Run All Test Files (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tr";
        action = "function() require('neotest').run.run() end";
        lua = true;
        options = {desc = "Run Nearest (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tl";
        action = "function() require('neotest').run.run_last() end";
        lua = true;
        options = {desc = "Run Last (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>ts";
        action = "function() require('neotest').summary.toggle() end";
        lua = true;
        options = {desc = "Toggle Summary (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>to";
        action = "function() require('neotest').output.open({ enter = true, auto_close = true }) end";
        lua = true;
        options = {desc = "Show Output (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tO";
        action = "function() require('neotest').output_panel.toggle() end";
        lua = true;
        options = {desc = "Toggle Output Panel (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tS";
        action = "function() require('neotest').run.stop() end";
        lua = true;
        options = {desc = "Stop (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>tw";
        action = "function() require('neotest').watch.toggle(vim.fn.expand('%')) end";
        lua = true;
        options = {desc = "Toggle Watch (Neotest)";};
      }
      {
        mode = "n";
        key = "<leader>td";
        action = "function() require('neotest').run.run({strategy = 'dap'}) end";
        lua = true;
        options = {desc = "Debug Nearest";};
      }
    ];

    binds.whichKey.setupOpts.spec = [
      {
        __unkeyed-1 = "<leader>t";
        group = "test";
        mode = "n";
      }
    ];
  };
}
