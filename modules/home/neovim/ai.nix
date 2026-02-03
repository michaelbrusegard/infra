{pkgs, ...}: {
  programs.nvf.settings.vim = {
    lazy.plugins = {
      "opencode.nvim" = {
        package = pkgs.vimPlugins.opencode-nvim;
        keys = [
          {
            key = "<leader>aa";
            action = ''function() require("opencode").ask("@this: ", { submit = true }) end'';
            lua = true;
            mode = ["n" "x"];
            desc = "Ask about this";
          }
          {
            key = "<leader>as";
            action = ''function() require("opencode").select() end'';
            lua = true;
            mode = ["n" "x"];
            desc = "Select prompt";
          }
          {
            key = "<leader>ac";
            action = ''function() require("opencode").prompt("@this") end'';
            lua = true;
            mode = ["n" "x"];
            desc = "Add this";
          }
          {
            key = "<leader>at";
            action = ''function() require("opencode").toggle() end'';
            lua = true;
            desc = "Toggle embedded";
          }
          {
            key = "<leader>an";
            action = ''function() require("opencode").command("session.new") end'';
            lua = true;
            desc = "New session";
          }
          {
            key = "<leader>ai";
            action = ''function() require("opencode").command("session.interrupt") end'';
            lua = true;
            desc = "Interrupt session";
          }
          {
            key = "<leader>aA";
            action = ''function() require("opencode").command("agent.cycle") end'';
            lua = true;
            desc = "Cycle selected agent";
          }
          {
            key = "<S-C-u>";
            action = ''function() require("opencode").command("session.half.page.up") end'';
            lua = true;
            desc = "Messages half page up";
          }
          {
            key = "<S-C-d>";
            action = ''function() require("opencode").command("session.half.page.down") end'';
            lua = true;
            desc = "Messages half page down";
          }
        ];
      };
    };

    binds.whichKey.setupOpts.spec = [
      {
        __unkeyed-1 = "<leader>a";
        group = "ai";
      }
    ];
  };
}
