# Manafish Stalwart v1 runner

This runner manages the company Stalwart v1.0.3 API with
`registry.opentofu.org/michaelbrusegard/stalwart` 1.0.3. The provider image is
pinned by digest in `kustomization.yaml`.

The image supplies BusyBox `/bin/cp` and an unpacked `linux_amd64` provider.
The init container copies `/provider-mirror/.` into the shared volume at
`/mnt/provider-mirror/`; the runner mounts it read-only at `/provider-mirror`.
The amd64 node selector matches that sole bundled architecture. Do not mount
the emptyDir over the init image's source directory.

The company stack's committed lock file contains `h1` hashes for this Linux
binary and its local Darwin validation build. `upgradeOnInit: false` retains
those selections/checksums; tf-controller otherwise defaults to init with
upgrade. The tofurc exclusively routes this provider through the filesystem
mirror. A changed binary needs a regenerated company lock and a new image pin,
not a registry fallback or a lock from only the Darwin build.

`backendConfig.secretSuffix: manafishrov-stalwart-v1` identifies the active
state. Keep this suffix stable. The company stack's retained imports adopt
existing objects by ID, including the relay secret, and prevent duplicates
when rebuilding state.

Terraform `manafishrov-stalwart` reconciles the company repository's
`tofu/stalwart` stack through tf-controller with the normal auto-approval
policy. Keep the server API, provider image and company lock file compatible
when updating either repository. Production plans and applies run in the
controller; local provider checks use `init -backend=false` and `validate`.
