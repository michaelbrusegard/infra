{pkgs, ...}: let
  jsTsFormatters = {
    oxfmt.package = pkgs.oxfmt;
    biome = {
      package = pkgs.biome;
      requiredFiles = ["biome.json" "biome.jsonc"];
    };
    prettier = {
      package = pkgs.prettier;
      requiredFiles = [
        ".prettierrc"
        ".prettierrc.json"
        ".prettierrc.yml"
        ".prettierrc.yaml"
        ".prettierrc.js"
        ".prettierrc.ts"
        ".prettierrc.cjs"
        ".prettierrc.mjs"
        "prettier.config.js"
        "prettier.config.ts"
        "prettier.config.cjs"
        "prettier.config.mjs"
      ];
    };
  };

  jsTsLinters = {
    oxlint = {
      package = pkgs.oxlint;
      requiredFiles = [
        ".oxlintrc.json"
        "oxlintrc.json"
      ];
    };
    biome = {
      package = pkgs.biome;
      requiredFiles = ["biome.json" "biome.jsonc"];
    };
    eslint = {
      package = pkgs.eslint;
      requiredFiles = [
        ".eslintrc.js"
        ".eslintrc.cjs"
        ".eslintrc.yaml"
        ".eslintrc.yml"
        ".eslintrc.json"
        "eslint.config.js"
        "eslint.config.mjs"
        "eslint.config.cjs"
        "eslint.config.ts"
      ];
    };
  };

  tsSettings = {
    updateImportsOnFileMove = {enabled = "always";};
    suggest = {
      completeFunctionCalls = true;
    };
    inlayHints = {
      enumMemberValues = {enabled = true;};
      functionLikeReturnTypes = {enabled = true;};
      parameterNames = {enabled = "literals";};
      parameterTypes = {enabled = true;};
      propertyDeclarationTypes = {enabled = true;};
      variableTypes = {enabled = false;};
    };
  };
in {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      typescript
      tsx
      javascript
      jsdoc
    ];

    lsp.servers.vtsls = {
      package = pkgs.vtsls;
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
        typescript = tsSettings;
        javascript = tsSettings;
      };
      onAttach = ''
        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
        end

        map("n", "gD", function()
          local params = vim.lsp.util.make_position_params(0, "utf-16")
          client:request("workspace/executeCommand", {
            command = "typescript.goToSourceDefinition",
            arguments = { params.textDocument.uri, params.position },
          }, function(err, result)
            if result and result[1] then
              vim.lsp.util.jump_to_location(result[1], "utf-16")
            end
          end)
        end, "Goto Source Definition")

        map("n", "gR", function()
          client:request("workspace/executeCommand", {
            command = "typescript.findAllFileReferences",
            arguments = { vim.uri_from_bufnr(0) },
          }, function(err, result)
            if result then
              vim.fn.setqflist(vim.lsp.util.locations_to_items(result, "utf-16"))
              vim.cmd("copen")
            end
          end)
        end, "File References")

        map("n", "<leader>co", function()
          vim.lsp.buf.code_action({
            apply = true,
            context = {
              only = { "source.organizeImports" },
              diagnostics = {},
            },
          })
        end, "Organize Imports")

        map("n", "<leader>cM", function()
          vim.lsp.buf.code_action({
            apply = true,
            context = {
              only = { "source.addMissingImports.ts" },
              diagnostics = {},
            },
          })
        end, "Add missing imports")

        map("n", "<leader>cu", function()
          vim.lsp.buf.code_action({
            apply = true,
            context = {
              only = { "source.removeUnused.ts" },
              diagnostics = {},
            },
          })
        end, "Remove unused imports")

        map("n", "<leader>cD", function()
          vim.lsp.buf.code_action({
            apply = true,
            context = {
              only = { "source.fixAll.ts" },
              diagnostics = {},
            },
          })
        end, "Fix all diagnostics")

        map("n", "<leader>cV", function()
          client:request("workspace/executeCommand", { command = "typescript.selectTypeScriptVersion" })
        end, "Select TS workspace version")

        client.commands["_typescript.moveToFileRefactoring"] = function(command, ctx)
          local action, uri, range = unpack(command.arguments)

          local function move(newf)
            client:request("workspace/executeCommand", {
              command = command.command,
              arguments = { action, uri, range, newf },
            })
          end

          local fname = vim.uri_to_fname(uri)
          client:request("workspace/executeCommand", {
            command = "typescript.tsserverRequest",
            arguments = {
              "getMoveToRefactoringFileSuggestions",
              {
                file = fname,
                startLine = range.start.line + 1,
                startOffset = range.start.character + 1,
                endLine = range["end"].line + 1,
                endOffset = range["end"].character + 1,
              },
            },
          }, function(_, result)
            local files = result.body.files
            table.insert(files, 1, "Enter new path...")
            vim.ui.select(files, {
              prompt = "Select move destination:",
              format_item = function(f)
                return vim.fn.fnamemodify(f, ":~:.")
              end,
            }, function(f)
              if f and f:find("^Enter new path") then
                vim.ui.input({
                  prompt = "Enter move destination:",
                  default = vim.fn.fnamemodify(fname, ":h") .. "/",
                  completion = "file",
                }, function(newf)
                  return newf and move(newf)
                end)
              elseif f then
                move(f)
              end
            end)
          end)
        end
      '';
    };

    formatting.filetypes = {
      javascript = jsTsFormatters;
      javascriptreact = jsTsFormatters;
      typescript = jsTsFormatters;
      typescriptreact = jsTsFormatters;
    };

    linting.filetypes = {
      javascript = jsTsLinters;
      javascriptreact = jsTsLinters;
      typescript = jsTsLinters;
      typescriptreact = jsTsLinters;
    };
  };
}
