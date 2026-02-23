_: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      theme = "catppuccin";
      plugin = ["oh-my-opencode"];
    };
  };
  home = {
    file.".config/opencode/oh-my-opencode.json".text = builtins.toJSON {
      "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json";
      categories = {
        visual-engineering = {
          model = "google/gemini-3.1-pro-preview";
        };
        ultrabrain = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        deep = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        artistry = {
          model = "opencode/glm-5-free";
        };
        writing = {
          model = "opencode/glm-5-free";
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
      };
      agents = {
        sisyphus = {
          model = "google/gemini-3-pro-preview";
        };
        oracle = {
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
        };
        librarian = {
          model = "opencode/glm-5-free";
        };
        explore = {
          model = "opencode/gpt-5-nano";
        };
        multimodal-looker = {
          model = "google/gemini-3-flash-preview";
        };
        document-writer = {
          model = "opencode/glm-5-free";
        };
      };
    };
    sessionVariables = {
      OPENCODE_EXPERIMENTAL_OXFMT = "true";
      OPENCODE_EXPERIMENTAL_EXA = "true";
      OPENCODE_EXPERIMENTAL_LSP_TOOL = "true";
      OPENCODE_EXPERIMENTAL_MARKDOWN = "true";
      OPENCODE_EXPERIMENTAL_PLAN_MODE = "true";
    };
  };
}
