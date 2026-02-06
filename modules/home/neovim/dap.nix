{pkgs, ...}: {
  programs.nvf.settings.vim = {
    debugger.nvim-dap = {
      enable = true;
      ui.enable = true;
      ui.autoStart = true;
      mappings = {
        continue = "<leader>dc";
        toggleBreakpoint = "<leader>db";
        stepInto = "<leader>di";
        stepOver = "<leader>dO";
        stepOut = "<leader>do";
        terminate = "<leader>dt";
        hover = "<leader>dw";
        runLast = "<leader>dl";
        runToCursor = "<leader>dC";
        goDown = "<leader>dj";
        goUp = "<leader>dk";
        toggleRepl = "<leader>dr";
        toggleDapUI = "<leader>du";
      };
    };

    lazy.plugins = {
      "nvim-dap-virtual-text" = {
        package = pkgs.vimPlugins.nvim-dap-virtual-text;
        setupModule = "nvim-dap-virtual-text";
        setupOpts = {};
      };
    };

    keymaps = [
      {
        key = "<leader>dB";
        mode = "n";
        desc = "Breakpoint Condition";
        action = "function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end";
        lua = true;
      }
      {
        key = "<leader>da";
        mode = "n";
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
        key = "<leader>dg";
        mode = "n";
        desc = "Go to Line (No Execute)";
        action = "function() require('dap').goto_() end";
        lua = true;
      }
      {
        key = "<leader>ds";
        mode = "n";
        desc = "Session";
        action = "function() require('dap').session() end";
        lua = true;
      }
      {
        key = "<leader>de";
        mode = ["n" "x"];
        desc = "Eval";
        action = "function() require('dapui').eval() end";
        lua = true;
      }
    ];

    luaConfigRC.dap-setup = ''
      local dap_icons = {
        Stopped             = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
        Breakpoint          = " ",
        BreakpointCondition = " ",
        BreakpointRejected  = { " ", "DiagnosticError" },
        LogPoint            = ".>",
      }

      for name, sign in pairs(dap_icons) do
        sign = type(sign) == "table" and sign or { sign }
        vim.fn.sign_define(
          "Dap" .. name,
          { text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
        )
      end
    '';
  };
}
