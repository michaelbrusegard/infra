# Codex reads /etc/codex/config.toml as its lowest-priority layer, so these
# defaults apply to every Codex client while ~/.codex/config.toml stays
# Codex's own file for project trust and TUI state.
{
  pkgs,
  lib,
  ...
}: let
  gateway = "https://ai.asgard.michaelbrusegard.com";
  aiImages = pkgs.callPackage ../../packages/ai-images {};
in {
  environment.systemPackages = [aiImages];
  environment.etc."codex/config.toml".source = (pkgs.formats.toml {}).generate "codex-config.toml" {
    # Codex is the reviewer harness; Claude Code writes the code.
    model = "gpt-6.1-sol";
    model_reasoning_effort = "high";
    model_provider = "cliproxyapi";
    model_providers.cliproxyapi = {
      name = "Asgard";
      base_url = "${gateway}/v1";
      model_catalog_url = "${gateway}/v1/models";
      # A non-secret placeholder that enables API-key model discovery:
      # NetBird authenticates the device and injects the upstream credential.
      experimental_bearer_token = "netbird";
      wire_api = "responses";
      requires_openai_auth = false;
      supports_websockets = false;
    };
    approval_policy = "never";
    sandbox_mode = "danger-full-access";
    apps._default.enabled = false;
    features.api_key_model_discovery = true;
    features.memories = false;
    # Codex's native image tool requires first-party provider/auth metadata.
    # Keep device authentication and expose the gateway's Images API via MCP.
    mcp_servers.ai_images = {
      command = lib.getExe aiImages;
      args = ["serve"];
      tool_timeout_sec = 660;
    };
    memories = {
      generate_memories = false;
      use_memories = false;
    };
  };
}
