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
    model = "gpt-6.2-sol";
    model_reasoning_effort = "high";
    model_provider = "cliproxy";
    model_providers.cliproxy = {
      name = "Asgard";
      base_url = "${gateway}/v1";
      model_catalog_url = "${gateway}/v1/models";
      # A non-secret placeholder that enables API-key model discovery:
      # NetBird authenticates the device and injects the upstream credential.
      experimental_bearer_token = "netbird";
      wire_api = "responses";
      requires_openai_auth = false;
      # Each turn sends only new input instead of the whole conversation.
      # NetBird cannot see a socket's messages, so it admits one only while
      # no policy restricts models; otherwise Codex falls back to SSE.
      supports_websockets = true;
      supports_standalone_web_search = true;
    };
    approval_policy = "never";
    sandbox_mode = "danger-full-access";
    # macOS ties a keychain "Always Allow" to the exact unsigned binary, and
    # every Nix rebuild or app-server update makes a new one, so the keychain
    # prompt would return each time. Keep MCP OAuth tokens in
    # ~/.codex/.credentials.json instead.
    mcp_oauth_credentials_store = "file";
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
    # Send OpenAI no metrics or /feedback uploads, and keep no prompt history.
    # Session rollouts stay: resume needs them and Codex has no switch for them.
    analytics.enabled = false;
    feedback.enabled = false;
    # Statsig is the exporter behind those metrics, sent to ab.chatgpt.com.
    otel.metrics_exporter = "none";
    history.persistence = "none";
  };
}
