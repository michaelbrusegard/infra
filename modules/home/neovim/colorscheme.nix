{pkgs, ...}: {
  programs.neovim.spec.plugins = {
    "catppuccin" = {
      package = pkgs.vimPlugins.catppuccin-nvim;
      event = ["UIEnter"];
      setupModule = "catppuccin";
      setupOpts = {
        lsp_styles = {
          underlines = {
            errors = ["undercurl"];
            hints = ["undercurl"];
            warnings = ["undercurl"];
            information = ["undercurl"];
          };
        };
        integrations = {
          alpha = false;
          blink_indent = false;
          blink_pairs = false;
          cmp = false;
          dashboard = false;
          flash = false;
          fzf = false;
          indent_blankline = {enabled = false;};
          neotree = false;
          neogit = false;
          nvimtree = false;
          rainbow_delimiters = false;
          render_markdown = false;
          telescope = {enabled = false;};
          illuminate = {enabled = false;};
          dap = true;
          dap_ui = true;
          grug_far = true;
          gitsigns = true;
          lsp_trouble = true;
          mini = true;
          navic = {
            enabled = true;
            custom_bg = "lualine";
          };
          neotest = true;
          noice = true;
          snacks = true;
          treesitter_context = true;
          which_key = true;
        };
      };
    };
  };
}
