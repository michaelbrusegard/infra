{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim.lazy.plugins = {
    "neotest" = {
      package = pkgs.vimPlugins.neotest;
      setupModule = "neotest";
      setupOpts = {
        status = {virtual_text = true;};
        output = {open_on_run = true;};
        quickfix = {
          open = lib.generators.mkLuaInline ''
            function()
              require("trouble").open({ mode = "quickfix", focus = false })
            end
          '';
        };
      };
      keys = [
        {
          key = "<leader>ta";
          mode = "n";
          desc = "Attach to Test (Neotest)";
          action = "function() require('neotest').run.attach() end";
          lua = true;
        }
        {
          key = "<leader>tt";
          mode = "n";
          desc = "Run File (Neotest)";
          action = "function() require('neotest').run.run(vim.fn.expand('%')) end";
          lua = true;
        }
        {
          key = "<leader>tT";
          mode = "n";
          desc = "Run All Test Files (Neotest)";
          action = "function() require('neotest').run.run(vim.uv.cwd()) end";
          lua = true;
        }
        {
          key = "<leader>tr";
          mode = "n";
          desc = "Run Nearest (Neotest)";
          action = "function() require('neotest').run.run() end";
          lua = true;
        }
        {
          key = "<leader>tl";
          mode = "n";
          desc = "Run Last (Neotest)";
          action = "function() require('neotest').run.run_last() end";
          lua = true;
        }
        {
          key = "<leader>ts";
          mode = "n";
          desc = "Toggle Summary (Neotest)";
          action = "function() require('neotest').summary.toggle() end";
          lua = true;
        }
        {
          key = "<leader>to";
          mode = "n";
          desc = "Show Output (Neotest)";
          action = "function() require('neotest').output.open({ enter = true, auto_close = true }) end";
          lua = true;
        }
        {
          key = "<leader>tO";
          mode = "n";
          desc = "Toggle Output Panel (Neotest)";
          action = "function() require('neotest').output_panel.toggle() end";
          lua = true;
        }
        {
          key = "<leader>tS";
          mode = "n";
          desc = "Stop (Neotest)";
          action = "function() require('neotest').run.stop() end";
          lua = true;
        }
        {
          key = "<leader>tw";
          mode = "n";
          desc = "Toggle Watch (Neotest)";
          action = "function() require('neotest').watch.toggle(vim.fn.expand('%')) end";
          lua = true;
        }
        {
          key = "<leader>td";
          mode = "n";
          desc = "Debug Nearest";
          action = "function() require('neotest').run.run({strategy = 'dap'}) end";
          lua = true;
        }
      ];
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
  };
}
