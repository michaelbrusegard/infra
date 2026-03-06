{pkgs, ...}: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      theme = "catppuccin";
      plugin = ["oh-my-opencode" "@simonwjackson/opencode-direnv"];
    };
  };
  home = {
    sessionVariables = {
      OPENCODE_EXPERIMENTAL_OXFMT = "true";
      OPENCODE_EXPERIMENTAL_EXA = "true";
      OPENCODE_EXPERIMENTAL_LSP_TOOL = "true";
      OPENCODE_EXPERIMENTAL_MARKDOWN = "true";
      OPENCODE_EXPERIMENTAL_PLAN_MODE = "true";
    };
    packages = with pkgs; [
      opencode-desktop
    ];
  };
}
