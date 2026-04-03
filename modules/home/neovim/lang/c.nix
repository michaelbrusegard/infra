{pkgs, lib, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      c
      cpp
      cmake
      make
    ];

    lsp.servers.clangd = {
      package = pkgs.clang-tools;
      onAttach = "require('clangd_extensions.inlay_hints').setup_autocmd()";
      config = {
        capabilities = {
          offsetEncoding = ["utf-16"];
        };
        cmd = [
          "${lib.getExe' pkgs.clang-tools "clangd"}"
          "--background-index"
          "--clang-tidy"
          "--header-insertion=iwyu"
          "--completion-style=detailed"
          "--function-arg-placeholders"
          "--fallback-style=llvm"
        ];
        init_options = {
          usePlaceholders = true;
          completeUnimported = true;
          clangdFileStatus = true;
        };
      };
    };

    lsp.servers.neocmake.package = pkgs.neocmakelsp;

    linting.filetypes.cmake.cmakelint.package = pkgs.cmake-lint;

    formatting.filetypes = {
      c.clang-format.package = pkgs.clang-tools;
      cpp.clang-format.package = pkgs.clang-tools;
      cmake.cmake-format.package = pkgs.cmake-format;
    };

    dap = {
      adapters.codelldb = {
        type = "server";
        port = "\${port}";
        executable = {
          command = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
          args = ["--port" "\${port}"];
        };
      };
      configurations = {
        c = [
          {
            name = "Launch file";
            type = "codelldb";
            request = "launch";
            program.__raw = ''function() return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file") end'';
            extraConfig = {
              cwd = "\${workspaceFolder}";
              stopOnEntry = false;
            };
          }
        ];
        cpp = [
          {
            name = "Launch file";
            type = "codelldb";
            request = "launch";
            program.__raw = ''function() return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file") end'';
            extraConfig = {
              cwd = "\${workspaceFolder}";
              stopOnEntry = false;
            };
          }
        ];
      };
    };

    plugins = {
      "clangd_extensions.nvim" = {
        package = pkgs.vimPlugins.clangd_extensions-nvim;
        filetype = ["c" "cpp" "objc" "objcpp" "cuda" "proto"];
        setupModule = "clangd_extensions";
        setupOpts = {
          inlay_hints = {inline = false;};
          ast = {
            role_icons = {
              type = "";
              declaration = "";
              expression = "";
              specifier = "";
              statement = "";
              "template argument" = "";
            };
            kind_icons = {
              Compound = " ";
              Recovery = "";
              TranslationUnit = "";
              PackExpansion = "";
              TemplateTypeParm = "";
              TemplateTemplateParm = "";
              TemplateParamObject = "";
            };
          };
        };
        keymaps = [
          {
            key = "<leader>ch";
            mode = "n";
            desc = "Switch Source/Header (C/C++)";
            action = "LspClangdSwitchSourceHeader";
          }
        ];
      };

      "cmake-tools.nvim" = {
        package = pkgs.vimPlugins.cmake-tools-nvim;
        filetype = ["cmake" "cpp" "c"];
        setupModule = "cmake-tools";
      };
    };
  };
}
