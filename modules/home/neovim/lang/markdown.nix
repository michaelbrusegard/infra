{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      markdown
      markdown-inline
    ];

    plugins."render-markdown.nvim" = {
      package = pkgs.vimPlugins.render-markdown-nvim;
      filetype = ["markdown" "rmd"];
      setupModule = "render-markdown";
      setupOpts = {
        code = {
          sign = false;
          width = "block";
          right_pad = 1;
        };
        heading = {
          sign = false;
          icons = [];
        };
        checkbox = {
          enabled = false;
        };
      };
    };

    plugins."markdown-preview.nvim" = {
      package = pkgs.vimPlugins.markdown-preview-nvim;
      filetype = ["markdown"];
      keymaps = [
        {
          key = "<leader>cp";
          action = "<cmd>MarkdownPreviewToggle<cr>";
          desc = "Markdown Preview";
        }
      ];
    };

    lsp.servers.marksman = {
      package = pkgs.marksman;
    };

    linting.filetypes = {
      markdown = {
        markdownlint.package = pkgs.markdownlint-cli2;
      };
      "markdown.mdx" = {
        markdownlint.package = pkgs.markdownlint-cli2;
      };
    };

    formatting.filetypes = {
      markdown = {
        oxfmt = {
          package = pkgs.oxfmt;
          args = ["--stdin-filepath" "$FILENAME"];
        };
        markdown-toc = {
          package = pkgs.markdown-toc;
          args = ["--no-firsth1"];
          condition = ''
            function(_, ctx)
              for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
                if line:find("<!%-%- toc %-%->") then
                  return true
                end
              end
            end
          '';
        };
      };
      "markdown.mdx" = {
        oxfmt = {
          package = pkgs.oxfmt;
          args = ["--stdin-filepath" "$FILENAME"];
        };
        markdown-toc = {
          package = pkgs.markdown-toc;
          args = ["--no-firsth1"];
          condition = ''
            function(_, ctx)
              for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
                if line:find("<!%-%- toc %-%->") then
                  return true
                end
              end
            end
          '';
        };
      };
    };
  };
}
