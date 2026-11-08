# Stalwart v1.0.3 provider

This package regenerates tahacodes/terraform-provider-stalwart at
`f7d85b3c5b0c8b2fafd31320f0476464584c8b8a` from Stalwart's v1.0.3 schema.
Both source downloads and the Go dependencies have fixed hashes in
`default.nix`. The enterprise schema includes fields used by the native SCIM
server; exposing a field does not enable its server implementation.

Use `source = "michaelbrusegard/stalwart"` and `version = "1.0.3"` in
`required_providers`. The full address is
`registry.opentofu.org/michaelbrusegard/stalwart`.

## Runner mirror

Build the Linux image with:

```sh
nix build .#packages.x86_64-linux.terraform-provider-stalwart-image -L
```

The image contains BusyBox at `/bin` and an executable, standalone Go binary
at this unpacked filesystem mirror path:

```text
/provider-mirror/registry.opentofu.org/michaelbrusegard/stalwart/1.0.3/linux_amd64/terraform-provider-stalwart_v1.0.3
```

Mount the shared mirror volume at `/mnt/provider-mirror` in the init
container, and at `/provider-mirror` in the tf-controller runner. Use this
init-container command:

```yaml
command: ["/bin/cp", "-R", "/provider-mirror/.", "/mnt/provider-mirror/"]
```

The runner's tofurc should contain:

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/provider-mirror"
    include = ["registry.opentofu.org/michaelbrusegard/stalwart"]
  }
  direct {
    exclude = ["registry.opentofu.org/michaelbrusegard/stalwart"]
  }
}
```

## Fresh-state migration

Singletons update the existing `singleton` object on create. Domains and
network listeners adopt the object returned by the server's unique-key
conflict and update its mutable fields. This does not provide adoption for
every resource type.

Keep import blocks for objects without a unique key: applications, OIDC
directories, certificates, DNS servers, tracers and inbound throttles.
Re-read their IDs after migrating the server. A create without an import
can duplicate them. Also import relay routes when their existing secret is
absent from the configuration: a create request must contain a valid secret
before the server can return a unique-key conflict.

Stalwart returns secrets as `****`. Patch 0004 omits a property containing a
masked sensitive field from writes, preserving the live secret. Ordinary
text equal to `****` remains writable. Account credentials retain the
server's own mask handling. Singleton destroy only removes state; destroying
an imported or adopted non-singleton deletes the server object.

## Local verification

Use a disposable upstream `stalwartlabs/stalwart:v1.0.3` container. In a
source tree made from the pinned upstream commit, apply the four patches,
decompress the pinned schema to `schema/v1.0.3.json`, then regenerate:

```sh
nix shell nixpkgs#go nixpkgs#opentofu
go run ./tools/generator schema/v1.0.3.json \
  internal/provider/generated.go internal/provider/generated_datasources.go
STALWART_CONTAINER=stalwart-provider-verify STALWART_PORT=18081 \
  bash scripts/acceptance-server.sh
TF_ACC=1 STALWART_URL=http://127.0.0.1:18081 \
  STALWART_USER=admin STALWART_PASSWORD=acctest123 \
  TF_ACC_PROVIDER_HOST=registry.opentofu.org \
  TF_ACC_PROVIDER_NAMESPACE=michaelbrusegard \
  TF_ACC_TERRAFORM_PATH="$(command -v tofu)" \
  go test ./... -count=1 -v -timeout=25m
```

The host and namespace overrides let the upstream test framework attach
the provider to OpenTofu. Without them its legacy Terraform address fails
during init.

From this repository, build the local binary and run the smoke test:

```sh
nix build .#terraform-provider-stalwart --out-link /tmp/stalwart-provider
nix shell nixpkgs#opentofu --command python3 \
  packages/terraform-provider-stalwart/tests/verify.py \
  --provider /tmp/stalwart-provider/bin/terraform-provider-stalwart \
  --work-dir /tmp/stalwart-provider-evidence
```

Use a new work directory and fresh container for each run. The smoke test
supports Colima's `host.docker.internal` address and serves temporary OIDC
metadata on the host. It verifies all five requested singletons, domain and
listener adoption, application and directory imports, and preservation of
an imported relay secret. It applies twice from separate empty states,
checks the same IDs and object counts, requires an empty second plan in
each state, and checks that an HTTP response header took effect after reload.
Logs, state and a provider schema dump go in the evidence directory.
The fixture does not test OIDC token authentication or serve application
assets. Remove the disposable test container after verification.
