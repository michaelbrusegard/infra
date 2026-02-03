{pkgs, ...}: {
  programs.nvf.settings.vim = {
    treesitter = {
      enable = true;
      highlight.enable = true;
      indent.enable = true;
      fold = true;
      grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        bash
        c
        diff
        html
        javascript
        jsdoc
        json
        jsonc
        lua
        luadoc
        luap
        markdown
        markdown-inline
        printf
        python
        query
        regex
        toml
        tsx
        typescript
        vim
        vimdoc
        xml
        yaml
      ];
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
    treesitter.autotagHtml = true;

    treesitter.context = {
      enable = true;
      setupOpts = {
        mode = "cursor";
        max_lines = 3;
      };
    };
  };
}
