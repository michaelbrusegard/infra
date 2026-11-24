{
  flake.modules.homeManager.helix = {
    programs.helix = {
      enable = true;

      settings = {
        editor = {
          # Matching neovim options
          mouse = true;
          scrolloff = 4;
          cursorline = true;
          auto-save = true;
          true-color = true;
          undercurl = true;
          rulers = [ ];
          color-modes = true;
          idle-timeout = 200;
          completion-timeout = 200;

          # Matching relativenumber + number
          line-number = "relative";
          gutters = [
            "diagnostics"
            "spacer"
            "line-numbers"
            "spacer"
            "diff"
          ];

          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };

          statusline = {
            left = [
              "mode"
              "spinner"
              "file-name"
              "read-only-indicator"
              "file-modification-indicator"
            ];
            center = [ ];
            right = [
              "diagnostics"
              "selections"
              "register"
              "position"
              "file-encoding"
              "file-line-ending"
              "file-type"
              "version-control"
            ];
            separator = "|";
            mode = {
              normal = "NORMAL";
              insert = "INSERT";
              select = "SELECT";
            };
          };

          # Matching list = true
          whitespace.render = {
            space = "none";
            tab = "all";
            nbsp = "all";
            nnbsp = "all";
            newline = "none";
          };

          indent-guides = {
            render = true;
            character = "│";
            skip-levels = 1;
          };

          # Matching linebreak = true, wrap = false by default
          soft-wrap.enable = false;

          file-picker = {
            hidden = false;
            git-ignore = true;
            git-global = true;
          };

          lsp = {
            display-messages = true;
            display-inlay-hints = true;
          };

          inline-diagnostics = {
            cursor-line = "hint";
            other-lines = "disable";
          };

          smart-tab.enable = true;
        };

        # Matching neovim keybinds where possible
        keys = {
          normal = {
            # Space as leader is default in helix

            C-h = "jump_view_left";
            C-j = "jump_view_down";
            C-k = "jump_view_up";
            C-l = "jump_view_right";

            # Escape clears search highlight (matching <esc> = noh)
            esc = [
              "collapse_selection"
              "keep_primary_selection"
            ];

            "[" = {
              b = "goto_previous_buffer";
            };
            "]" = {
              b = "goto_next_buffer";
            };

            # [d and ]d are default in helix

            space = {
              "-" = "hsplit";
              "|" = "vsplit";

              b = {
                b = "buffer_picker";
                D = ":buffer-close";
              };

              f = {
                f = "file_picker";
                n = ":new";
                r = "file_picker_in_current_buffer_directory";
                g = "file_picker_in_current_directory";
              };

              c = {
                a = "code_action";
                f = ":format";
                r = "rename_symbol";
                d = "diagnostics_picker";
                s = "symbol_picker";
                S = "workspace_symbol_picker";
              };

              s = {
                g = "global_search";
                s = "symbol_picker";
                b = "buffer_picker";
              };

              w = {
                d = ":quit";
                h = "jump_view_left";
                j = "jump_view_down";
                k = "jump_view_up";
                l = "jump_view_right";
              };

              q = {
                q = ":quit";
                a = ":quit-all";
              };
            };

            g = {
              d = "goto_definition";
              D = "goto_declaration";
              r = "goto_reference";
              i = "goto_implementation";
              t = "goto_type_definition";
            };
          };

          select = {
            C-h = "jump_view_left";
            C-j = "jump_view_down";
            C-k = "jump_view_up";
            C-l = "jump_view_right";
          };

          insert = {
            esc = "normal_mode";
          };
        };
      };

      # Matching neovim lang configs for formatting/LSP
      languages = {
        language-server = {
          nixd = {
            command = "nixd";
          };
          typescript-language-server = {
            command = "typescript-language-server";
            args = [ "--stdio" ];
          };
          rust-analyzer = {
            command = "rust-analyzer";
          };
          pylsp = {
            command = "pylsp";
          };
        };

        language = [
          {
            name = "nix";
            formatter = {
              command = "nixfmt";
            };
            language-servers = [ "nixd" ];
            auto-format = true;
          }
          {
            name = "typescript";
            auto-format = true;
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "tsx";
            auto-format = true;
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "javascript";
            auto-format = true;
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "jsx";
            auto-format = true;
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "rust";
            auto-format = true;
            language-servers = [ "rust-analyzer" ];
          }
          {
            name = "python";
            auto-format = true;
            language-servers = [ "pylsp" ];
          }
          {
            name = "json";
            auto-format = true;
          }
          {
            name = "yaml";
            auto-format = true;
          }
          {
            name = "toml";
            auto-format = true;
          }
          {
            name = "markdown";
            auto-format = true;
            soft-wrap.enable = true;
          }
        ];
      };
    };
  };
}
