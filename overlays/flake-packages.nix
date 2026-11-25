inputs: _: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
in
{
  inherit (inputs.hyprland.packages.${system}) hyprland xdg-desktop-portal-hyprland;

  quickshell = inputs.quickshell.packages.${system}.default;
  dms-shell = inputs.dms.packages.${system}.default;
  dux-files = inputs.dux-files.packages.${system}.default;
  bubbles = inputs.bubbles.packages.${system}.default;
  inherit (inputs.llm-agents.packages.${system}) chatgpt claude-code codex;
  opencode = inputs.llm-agents.packages.${system}.opencode2;
  pi-coding-agent = inputs.llm-agents.packages.${system}.pi;
  t3code = prev.callPackage ../packages/t3code {
    unwrapped = inputs.t3code.packages.${system}.t3-code;
  };
}
