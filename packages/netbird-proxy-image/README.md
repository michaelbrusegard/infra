# NetBird image routing

NetBird 0.81.3's Agent Network parser does not recognize the OpenAI Images
endpoints. Requests to `/v1/images/generations` and `/v1/images/edits` fail with
`403 missing llm.model on request envelope` before reaching CLIProxyAPI.
Multipart edits also need model extraction from form fields. Changing the
provider's catalog type does not fix the synthesized parser configuration.

This image retains the upstream runtime and replaces its proxy binary with a
patched build of the same source revision. The patch recognizes both image
endpoints and recovers model/stream from multipart forms using the existing
bounded routing scan. It preserves the original upload bytes. Duplicate model
fields, malformed forms and multipart bodies over the 32 MiB scan limit fail
closed. Image requests still pass through the existing group, model and quota
checks. Prompt capture remains controlled by the existing account setting;
multipart routing recovery never captures the image or prompt as log metadata.

The build runs the upstream parser/router/guardrail tests plus regression
tests for HTTP forwarding, uploads larger than the normal 1 MiB capture limit,
model denials, group denials, and existing Claude/Responses requests.

```sh
docker build -t netbird-proxy:images packages/netbird-proxy-image
```

The `NetBird Proxy Image` workflow builds on PRs. On main it publishes to
`ghcr.io/michaelbrusegard/netbird-proxy`, checks that an unauthenticated client
can pull the image, then commits its immutable digest into the Agent Network
StatefulSet. The existing image keeps running until that promotion succeeds.
The new GHCR package needs public read access, or the workload and pull check
must first be configured for private registry credentials. The workflow does
not change package visibility. It uses the existing `image-bump` environment
and `IMAGE_BUMP_DEPLOY_KEY` used by the other image workflows.

Keep the upstream source revision, archive checksum, runtime image and patch
compatible when updating. Remove the patch after upstream supports these
requests and the same tests pass without it.

## Shared access

The live `Shared AI Access` policy binds the `AI` group to CLIProxyAPI and uses
the `Shared AI models` guardrail. At the time of diagnosis its allowlist was:

- `gpt-6.1-sol`
- `kimi-k3.1-pro`

To allow image generation for an existing member of that group, add
`gpt-image-2.5-sunburst` to **Shared AI models → Model allowlist**. Optionally
add `gpt-image-2.5-flare` and/or `gpt-image-2` if those models should also be
available. Keep the text models and the guardrail enabled. No additional
network policy or personal OpenAI API key is needed for this gateway route.
The CLIProxyAPI account selected upstream must have access and remaining quota.

Dashboard policy edits survive bootstrap restarts. This change does not
automatically widen anyone's model permissions.

## Other compatibility limits

- Codex's native image extension is hidden for the custom provider. Setting
  `requires_openai_auth = true` would also require a local OpenAI login.
  `modules/common/codex.nix` instead registers the `ai-images` MCP server;
  it uses the existing device-authenticated gateway. Apply the host config
  and start a new Codex process to load it.
- NetBird's current parser also omits CLIProxyAPI's speech, video, alpha
  search and live-session endpoints. Model-less video polling and WebSocket
  handshakes need authorization tied to their session/model, not a blanket
  allow rule. Those protocols remain outside this image patch.
- Codex deliberately disables connected apps (`apps._default.enabled = false`)
  and WebSocket transport in the system configuration. MCP tools and HTTP
  response streaming are separate and remain available. A missing connected
  app is not evidence that CLIProxyAPI lacks the corresponding model feature.
- The gateway captures at most 8 MiB of response data for accounting. Large
  base64 image responses may put usage after that prefix, and its text-token
  pricing table does not describe image pricing. Do not treat dashboard dollar
  totals or budget limits as reliable image-cost controls. Upstream account
  limits still apply; the shared policy currently has token/budget caps off.
- Multipart requests above 32 MiB remain unsupported by the bounded routing
  scan. The image client rejects JSON requests above 30 MiB before uploading;
  use smaller references when needed. These limits concern request size, not
  the generated wallpaper's dimensions.
