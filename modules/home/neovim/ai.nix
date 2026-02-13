{pkgs, ...}: {
  programs.neovim.spec = {
    globals.opencode_opts.provider = {
      enabled = "snacks";
      cmd = "${pkgs.opencode}/bin/opencode --port";
    };
    plugins = {
      "opencode.nvim" = {
        package = pkgs.vimPlugins.opencode-nvim;
        keymaps = [
          {
            key = "<leader>aa";
            mode = ["n" "x"];
            desc = "Ask about this";
            action = "function() require('opencode').ask('@this: ', { submit = true }) end";
            lua = true;
          }
          {
            key = "<leader>as";
            mode = ["n" "x"];
            desc = "Select prompt";
            action = "function() require('opencode').select() end";
            lua = true;
          }
          {
            key = "<leader>ac";
            mode = ["n" "x"];
            desc = "Add this";
            action = "function() require('opencode').prompt('@this') end";
            lua = true;
          }
          {
            key = "<leader>at";
            mode = ["n" "x"];
            desc = "Toggle embedded";
            action = "function() require('opencode').toggle() end";
            lua = true;
          }
          {
            key = "<leader>an";
            mode = ["n"];
            desc = "New session";
            action = "function() require('opencode').command('session.new') end";
            lua = true;
          }
          {
            key = "<leader>ai";
            mode = ["n"];
            desc = "Interrupt session";
            action = "function() require('opencode').command('session.interrupt') end";
            lua = true;
          }
          {
            key = "<leader>aA";
            mode = ["n"];
            desc = "Cycle selected agent";
            action = "function() require('opencode').command('agent.cycle') end";
            lua = true;
          }
          {
            key = "<S-C-u>";
            mode = ["n"];
            desc = "Messages half page up";
            action = "function() require('opencode').command('session.half.page.up') end";
            lua = true;
          }
          {
            key = "<S-C-d>";
            mode = ["n"];
            desc = "Messages half page down";
            action = "function() require('opencode').command('session.half.page.down') end";
            lua = true;
          }
        ];
      };
    };
  };
}
