{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim = {
    treesitter = {
      enable = true;
      grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        javascript
        typescript
        tsx
      ];
    };

    lsp.servers = {
      vtsls = {
        root_markers = ["tsconfig.json" "package.json" "jsconfig.json"];
        filetypes = ["javascript" "javascriptreact" "javascript.jsx" "typescript" "typescriptreact" "typescript.tsx"];
        cmd = [(lib.getExe pkgs.vtsls) "--stdio"];
        settings = {
          complete_function_calls = true;
          vtsls = {
            enableMoveToFileCodeAction = true;
            autoUseWorkspaceTsdk = true;
            experimental = {
              maxInlayHintLength = 30;
              completion = {
                enableServerSideFuzzyMatch = true;
              };
            };
          };
          typescript = {
            updateimportsonfilemove = {enabled = "always";};
            suggest = {
              completefunctioncalls = true;
            };
            inlayhints = {
              enummembervalues = {enabled = true;};
              functionlikereturntypes = {enabled = true;};
              parameternames = {enabled = "literals";};
              parametertypes = {enabled = true;};
              propertydeclarationtypes = {enabled = true;};
              variabletypes = {enabled = false;};
            };
          };
          javascript = {
            updateimportsonfilemove = {enabled = "always";};
            suggest = {
              completefunctioncalls = true;
            };
            inlayhints = {
              enummembervalues = {enabled = true;};
              functionlikereturntypes = {enabled = true;};
              parameternames = {enabled = "literals";};
              parametertypes = {enabled = true;};
              propertydeclarationtypes = {enabled = true;};
              variabletypes = {enabled = false;};
            };
          };
        };
      };

      eslint = {
        root_markers = [".eslintrc.js" ".eslintrc.json" ".eslintrc" "eslint.config.js" "eslint.config.mjs" "eslint.config.cjs" "package.json"];
        filetypes = ["javascript" "javascriptreact" "javascript.jsx" "typescript" "typescriptreact" "typescript.tsx"];
        cmd = [(lib.getExe pkgs.eslint) "--stdio"];
      };

      # Oxlint LSP (conditional)
      oxlint = {
        cmd = [(lib.getExe pkgs.oxlint) "--lsp"];
        filetypes = tsFiletypes;
        root_markers = [".oxlintrc.json" "package.json" ".git"];
        condition = mkLuaInline ''
          function(bufnr, root_dir)
            return vim.fn.filereadable(root_dir .. "/.oxlintrc.json") == 1
          end
        '';
      };
    };

    # 3. Formatting (conform-nvim)
    formatter.conform-nvim = {
      enable = true;
      setupOpts = {
        formatters_by_ft = {
          javascript = ["oxfmt" "biome" "prettier"];
          javascriptreact = ["oxfmt" "biome" "prettier"];
          typescript = ["oxfmt" "biome" "prettier"];
          typescriptreact = ["oxfmt" "biome" "prettier"];
        };
        formatters = {
          oxfmt = {
            command = lib.getExe pkgs.oxfmt;
            args = ["--stdin"];
            condition = mkLuaInline ''
              function(ctx)
                return vim.fn.filereadable(ctx.cwd .. "/.oxlintrc.json") == 1
                  or vim.fn.filereadable(ctx.cwd .. "/oxlint.json") == 1
              end
            '';
          };
          biome = {
            command = lib.getExe pkgs.biome;
            args = ["format" "--stdin-file-path" "$FILENAME"];
            require_cwd = true;
            condition = mkLuaInline ''
              function(ctx)
                return vim.fn.filereadable(ctx.cwd .. "/biome.json") == 1
                  or vim.fn.filereadable(ctx.cwd .. "/biome.jsonc") == 1
              end
            '';
          };
          prettier = {
            condition = mkLuaInline ''
              function(ctx)
                local function has_config(path)
                  vim.fn.system({"prettier", "--find-config-path", path})
                  return vim.v.shell_error == 0
                end
                return has_config(ctx.filename)
              end
            '';
          };
        };
      };
    };

    # 4. Linting (nvim-lint)
    diagnostics.nvim-lint = {
      enable = true;
      linters_by_ft = {
        javascript = ["oxlint" "eslint_d"];
        javascriptreact = ["oxlint" "eslint_d"];
        typescript = ["oxlint" "eslint_d"];
        typescriptreact = ["oxlint" "eslint_d"];
      };
      linters = {
        oxlint = {
          cmd = lib.getExe pkgs.oxlint;
          args = ["--format=compact" "--stdin" "--stdin-filename=%filepath"];
          stdin = true;
          condition = mkLuaInline ''
            function(ctx)
              return vim.fn.filereadable(ctx.cwd .. "/.oxlintrc.json") == 1
            end
          '';
        };
        eslint_d = {
          cmd = lib.getExe pkgs.eslint_d;
          args = ["--stdin" "--stdin-filename=%filepath" "--format=compact"];
          stdin = true;
        };
      };
    };

    # 5. Plugins (lazy-loaded)
    lazy.plugins = {
      # TypeScript error translator
      "ts-error-translator.nvim" = {
        package = pkgs.vimPlugins.ts-error-translator-nvim;
        setupModule = "ts-error-translator";
        setupOpts = {};
        event = [
          {
            event = "User";
            pattern = "LazyFile";
          }
        ];
        ft = tsFiletypes;
      };

      # Neotest adapters
      "neotest-jest" = {
        package = pkgs.vimPlugins.neotest-jest;
        setupModule = "neotest-jest";
        setupOpts = {};
        after = ["neotest"];
        ft = tsFiletypes;
      };
      "neotest-vitest" = {
        package = pkgs.vimPlugins.neotest-vitest;
        setupModule = "neotest-vitest";
        setupOpts = {};
        after = ["neotest"];
        ft = tsFiletypes;
      };
    };

    # 6. DAP configuration (if needed)
    debugger.nvim-dap = {
      enable = true;
      sources = {
        typescript-debugger = ''
          require('dap').adapters.node2 = {
            type = 'executable',
            command = 'node',
            args = {os.getenv('HOME') .. '/.local/share/nvim/mason/packages/node-debug2-adapter/out/src/nodeDebug.js'},
          }
          require('dap').configurations.javascript = {
            {
              name = 'Launch',
              type = 'node2',
              request = 'launch',
              program = '${"$"}{file}',
              cwd = vim.fn.getcwd(),
              sourceMaps = true,
              protocol = 'inspector',
              console = 'integratedTerminal',
            },
          }
          require('dap').configurations.typescript = require('dap').configurations.javascript
        '';
      };
    };
  };
}
