{pkgs, ...}: {
  programs.nvf.settings.vim.treesitter = {
    enable = true;
    highlight.enable = true;
    indent.enable = true;
    fold = true;
    autotagHtml = true;
    grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      bash
      diff
      html
      printf
      json
      markdown
      markdown-inline
      query
      regex
      toml
      vim
      vimdoc
      xml
      yaml
      http
    ];
    context = {
      enable = true;
      setupOpts = {
        mode = "cursor";
        max_lines = 3;
      };
    };
    textobjects = {
      enable = true;
      setupOpts = {
        move = {
          enable = true;
          set_jumps = true;
          goto_next_start = {
            "]f" = "@function.outer";
            "]c" = "@class.outer";
            "]a" = "@parameter.inner";
          };
          goto_next_end = {
            "]F" = "@function.outer";
            "]C" = "@class.outer";
            "]A" = "@parameter.inner";
          };
          goto_previous_start = {
            "[f" = "@function.outer";
            "[c" = "@class.outer";
            "[a" = "@parameter.inner";
          };
          goto_previous_end = {
            "[F" = "@function.outer";
            "[C" = "@class.outer";
            "[A" = "@parameter.inner";
          };
        };
      };
    };
  };
}
