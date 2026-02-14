{pkgs, ...}: {
  programs.neovim.spec.dap.keymaps = [
    {
      key = "<leader>dB";
      mode = ["n"];
      desc = "Breakpoint Condition";
      action = "function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end";
      lua = true;
    }
    {
      key = "<leader>db";
      mode = ["n"];
      desc = "Toggle Breakpoint";
      action = "function() require('dap').toggle_breakpoint() end";
      lua = true;
    }
    {
      key = "<leader>dc";
      mode = ["n"];
      desc = "Run/Continue";
      action = "function() require('dap').continue() end";
      lua = true;
    }
    {
      key = "<leader>da";
      mode = ["n"];
      desc = "Run with Args";
      action = ''
        function()
          local args = vim.fn.input("Run with args: ")
          require('dap').continue({ before = function(config)
            config.args = require('dap.utils').splitstr(args)
            return config
          end })
        end
      '';
      lua = true;
    }
    {
      key = "<leader>dC";
      mode = ["n"];
      desc = "Run to Cursor";
      action = "function() require('dap').run_to_cursor() end";
      lua = true;
    }
    {
      key = "<leader>dg";
      mode = ["n"];
      desc = "Go to Line (No Execute)";
      action = "function() require('dap').goto_() end";
      lua = true;
    }
    {
      key = "<leader>di";
      mode = ["n"];
      desc = "Step Into";
      action = "function() require('dap').step_into() end";
      lua = true;
    }
    {
      key = "<leader>dj";
      mode = ["n"];
      desc = "Down";
      action = "function() require('dap').down() end";
      lua = true;
    }
    {
      key = "<leader>dk";
      mode = ["n"];
      desc = "Up";
      action = "function() require('dap').up() end";
      lua = true;
    }
    {
      key = "<leader>dl";
      mode = ["n"];
      desc = "Run Last";
      action = "function() require('dap').run_last() end";
      lua = true;
    }
    {
      key = "<leader>do";
      mode = ["n"];
      desc = "Step Out";
      action = "function() require('dap').step_out() end";
      lua = true;
    }
    {
      key = "<leader>dO";
      mode = ["n"];
      desc = "Step Over";
      action = "function() require('dap').step_over() end";
      lua = true;
    }
    {
      key = "<leader>dP";
      mode = ["n"];
      desc = "Pause";
      action = "function() require('dap').pause() end";
      lua = true;
    }
    {
      key = "<leader>dr";
      mode = ["n"];
      desc = "Toggle REPL";
      action = "function() require('dap').repl.toggle() end";
      lua = true;
    }
    {
      key = "<leader>ds";
      mode = ["n"];
      desc = "Session";
      action = "function() require('dap').session() end";
      lua = true;
    }
    {
      key = "<leader>dt";
      mode = ["n"];
      desc = "Terminate";
      action = "function() require('dap').terminate() end";
      lua = true;
    }
    {
      key = "<leader>dw";
      mode = ["n"];
      desc = "Widgets";
      action = "function() require('dap.ui.widgets').hover() end";
      lua = true;
    }
  ];

  programs.neovim.spec.plugins = {
    "nvim-dap-virtual-text" = {
      package = pkgs.vimPlugins.nvim-dap-virtual-text;
      setupModule = "nvim-dap-virtual-text";
      after = "nvim-dap";
    };

    "nvim-dap-view" = {
      package = pkgs.vimPlugins.nvim-dap-view;
      setupModule = "dap-view";
      after = "nvim-dap";
      keymaps = [
        {
          key = "<leader>du";
          mode = ["n"];
          desc = "Dap UI";
          action = "function() require('dap-view').toggle() end";
          lua = true;
        }
        {
          key = "<leader>de";
          mode = ["n" "x"];
          desc = "Eval";
          action = "function() require('dap-view').add_expr() end";
          lua = true;
        }
      ];
      extraLuaAfter = ''
        local dap = require("dap")
        local dap_view = require("dap-view")

        dap.listeners.after.event_initialized["dap-view"] = function()
          dap_view.open()
        end
        dap.listeners.before.event_terminated["dap-view"] = function()
          dap_view.close()
        end
        dap.listeners.before.event_exited["dap-view"] = function()
          dap_view.close()
        end
      '';
    };
  };
}
