# Shared image tools

`ai-images` sends generation and editing requests through
`https://ai.asgard.michaelbrusegard.com/v1`. NetBird authenticates the device
and enforces the shared model policy; the client needs no personal API key.
It defaults to `gpt-image-2.5-sunburst` at 3840 × 2160, high quality.

Codex loads the MCP server from the system configuration in
`modules/common/codex.nix`. Its tools are `generate_image` and `edit_image`.
Other MCP clients can launch `ai-images serve` over stdio. The CLI also works:

```sh
ai-images generate \
  --prompt 'Image 1 is the target. Apply the brushwork of image 2; preserve the composition and sunset palette.' \
  --reference /absolute/path/to/target.jpg \
  --reference /absolute/path/to/style.png \
  --output /absolute/path/to/result.png
```

Omit references to generate a new image. Reference order is preserved. Output
paths must be absolute and new; the client never overwrites an existing file.
Images must be PNG, JPEG or WebP. The total JSON request is capped at 30 MiB,
including base64 expansion. The client does not follow gateway redirects or
fall back to a different provider/model after a failure.

The Nix package runs HTTP fixture tests and an actual MCP stdio handshake/tool
call. No live image generation occurs during tests. See
[`netbird-proxy-image`](../netbird-proxy-image/README.md) for gateway rollout,
shared-policy setup and known compatibility limits.
