Agent Network serves `https://ai.asgard.michaelbrusegard.com/v1` exclusively
over NetBird. NetBird publishes the endpoint's private DNS record to authorized
peers. No public DNS record, HTTPRoute, or public HTTP listener is needed.
cert-manager issues its certificate with the existing DNS-01 ClusterIssuer.

The `AI` group is owned by the NetBird OpenTofu stack. The proxy's init container
waits for that group, then configures the dedicated endpoint, CLIProxyAPI
provider, and `Shared AI Access` policy through the NetBird 0.77 management API.
Initially, `Admins` and `AI` can use the endpoint. The init container preserves
an existing endpoint and fails if its address differs from this configuration.

The pinned NetBird OpenTofu provider (0.0.9) does not expose Agent Network
resources, so the init container handles these API objects while OpenTofu
continues to own network groups.

Manage membership in NetBird: under Team > Users, assign `AI` to a user's
auto-assigned groups. Existing group propagation applies it to their devices.
Remove that membership to revoke access. The bootstrap never changes users,
roles, or group membership, so revocation survives proxy restarts.

`config.json` supplies defaults when creating the provider: all upstream
models are allowed. Use Agent Network > Providers to restrict models, and
Agent Network > Policies to set usage limits or disable access. Existing
dashboard settings survive proxy restarts and upstream-key rotation. The
bootstrap recreates missing providers and policies; disable them rather than
deleting them when suspending access.

No token or budget caps are enabled initially, and prompt collection is off.
The bootstrap refuses to overwrite an existing provider's type or upstream
address, preventing its credential from being forwarded to another service.

The existing management PAT is available through the reflected
`netbird-credentials` Secret and is mounted only into the init container. The
bootstrap and proxy use the existing HTTPS management endpoint. The
upstream key is reflected from the existing `cliproxyapi` Secret into NetBird's
namespace. Rotating that one source updates both consumers, and the bootstrap
updates the provider key without resetting dashboard controls. Neither key is
passed to clients. The proxy's separate account-scoped
registration token is generated on first deployment, stored with mode 0600 on
its PVC, and reused on restart. Revoke it in NetBird if retiring the proxy.

Roll out the encrypted Secret's reflection annotations before the infra changes. Flux reads these
Kubernetes secrets directly from the secrets GitRepository; no secrets flake
lock update is required for these manifests. After rollout, check the bootstrap
logs, proxy readiness, certificate readiness, and a streaming Responses request
from an authorized NetBird client. Also verify that an unauthorized peer is
denied. Client configuration remains a separate step.

`llm.asgard.michaelbrusegard.com` remains the direct, API-key-protected endpoint.
Its existing LAN and routed-network access rules are unchanged. Domain-based
network resources sharing the internal gateway IP do not isolate virtual hosts;
the `Infra` resource label alone is not an application authorization boundary.

Run the bootstrap regression checks with:

```sh
python3 -m unittest discover -s gitops/espresso/apps/netbird/agent-network -p 'test_*.py'
```
