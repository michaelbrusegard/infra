{pkgs, ...}: {
  programs.neovim = {
    spec = {
      treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        rust
        ron
      ];

      plugins = {
        "rustaceanvim" = {
          package = pkgs.vimPlugins.rustaceanvim;
          filetype = ["rust"];
          extraLuaBefore = ''
            local extension_path = '${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/'
            local codelldb_path = extension_path .. 'adapter/codelldb'
            local liblldb_path = extension_path .. 'lldb/lib/liblldb${
              if pkgs.stdenv.isDarwin
              then ".dylib"
              else ".so"
            }'

            vim.g.rustaceanvim = {
              server = {
                on_attach = function(client, bufnr)
                  vim.keymap.set("n", "<leader>cR", function()
                    vim.cmd.RustLsp("codeAction")
                  end, { desc = "Code Action", buffer = bufnr })
                  vim.keymap.set("n", "<leader>dr", function()
                    vim.cmd.RustLsp("debuggables")
                  end, { desc = "Rust Debuggables", buffer = bufnr })
                end,
                default_settings = {
                  ["rust-analyzer"] = {
                    cargo = {
                      allFeatures = true,
                      loadOutDirsFromCheck = true,
                      buildScripts = {
                        enable = true,
                      },
                    },
                    checkOnSave = true,
                    procMacro = {
                      enable = true,
                    },
                    files = {
                      exclude = {
                        ".direnv",
                        ".git",
                        ".jj",
                        ".github",
                        "bin",
                        "node_modules",
                        "target",
                        "venv",
                        ".venv",
                      },
                      watcher = "client",
                    },
                  },
                },
              },
              dap = {
                adapter = require("rustaceanvim.config").get_codelldb_adapter(codelldb_path, liblldb_path),
              },
            }
          '';
        };

        "crates" = {
          package = pkgs.vimPlugins.crates-nvim;
          event = ["BufRead"];
          condition = "vim.fn.expand('%:t') == 'Cargo.toml'";
          setupModule = "crates";
          setupOpts = {
            completion = {
              crates = {
                enabled = true;
              };
            };
            lsp = {
              enabled = true;
              actions = true;
              completion = true;
              hover = true;
            };
          };
        };
      };
    };
    extraPackages = [
      pkgs.rust-analyzer
      pkgs.rustfmt
      pkgs.clippy
    ];
  };
}
