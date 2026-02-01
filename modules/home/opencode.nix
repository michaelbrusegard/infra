{pkgs, ...}: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      theme = "catppuccin";
      plugin = ["oh-my-opencode" "opencode-beads" "opencode-antigravity-auth@beta" "@tarquinen/opencode-dcp@latest"];
      model = "opencode/kimi-k2.5-free";
      small_model = "opencode/gpt-5-nano";
      provider = {
        google = {
          models = {
            antigravity-gemini-3-pro = {
              name = "Gemini 3 Pro (Antigravity)";
              limit = {
                context = 1048576;
                output = 65535;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
              variants = {
                low = {thinkingLevel = "low";};
                high = {thinkingLevel = "high";};
              };
            };
            antigravity-gemini-3-flash = {
              name = "Gemini 3 Flash (Antigravity)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
              variants = {
                minimal = {thinkingLevel = "minimal";};
                low = {thinkingLevel = "low";};
                medium = {thinkingLevel = "medium";};
                high = {thinkingLevel = "high";};
              };
            };
            antigravity-claude-sonnet-4-5 = {
              name = "Claude Sonnet 4.5 (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            antigravity-claude-sonnet-4-5-thinking = {
              name = "Claude Sonnet 4.5 Thinking (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
              variants = {
                low = {thinkingConfig = {thinkingBudget = 8192;};};
                max = {thinkingConfig = {thinkingBudget = 32768;};};
              };
            };
            antigravity-claude-opus-4-5-thinking = {
              name = "Claude Opus 4.5 Thinking (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
              variants = {
                low = {thinkingConfig = {thinkingBudget = 8192;};};
                max = {thinkingConfig = {thinkingBudget = 32768;};};
              };
            };
            "gemini-2.5-flash" = {
              name = "Gemini 2.5 Flash (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "gemini-2.5-pro" = {
              name = "Gemini 2.5 Pro (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "gemini-3-flash-preview" = {
              name = "Gemini 3 Flash Preview (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "gemini-3-pro-preview" = {
              name = "Gemini 3 Pro Preview (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65535;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
          };
        };
      };
    };
  };
  home = {
    file.".config/opencode/oh-my-opencode.json".text = builtins.toJSON {
      "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json";
      google_auth = false;
      agents = {
        sisyphus = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        oracle = {
          model = "opencode/glm-4.7-free";
        };
        librarian = {
          model = "opencode/glm-4.7-free";
        };
        explore = {
          model = "opencode/glm-4.7-free";
        };
        multimodal-looker = {
          model = "opencode/glm-4.7-free";
        };
        prometheus = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        metis = {
          model = "opencode/glm-4.7-free";
        };
        momus = {
          model = "opencode/glm-4.7-free";
        };
        atlas = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
      };
      categories = {
        visual-engineering = {
          model = "google/antigravity-gemini-3-pro";
        };
        ultrabrain = {
          model = "google/antigravity-claude-opus-4-5-thinking";
        };
        artistry = {
          model = "opencode/glm-4.7-free";
        };
        quick = {
          model = "opencode/gpt-5-nano";
        };
        unspecified-low = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        unspecified-high = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        writing = {
          model = "google/antigravity-gemini-3-flash";
        };
      };
    };
    packages = with pkgs; [
      beads
    ];
    sessionVariables = {
      OPENCODE_EXPERIMENTAL_OXFMT = "true";
      OPENCODE_EXPERIMENTAL_EXA = "true";
      OPENCODE_EXPERIMENTAL_LSP_TOOL = "true";
      OPENCODE_EXPERIMENTAL_MARKDOWN = "true";
      OPENCODE_EXPERIMENTAL_PLAN_MODE = "true";
    };
  };
}
