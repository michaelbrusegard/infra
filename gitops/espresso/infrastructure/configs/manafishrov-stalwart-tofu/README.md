# Manafish Stalwart v1 runner

This runner is for the patched Stalwart v1.0.3 API and
`registry.opentofu.org/michaelbrusegard/stalwart` 1.0.3. Fill the provider image
tag/digest in `kustomization.yaml` from the published artifact built at
`2e56442a19603f49e0266ca6004aa06cce6e2595` before rollout.

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

`backendConfig.secretSuffix: manafishrov-stalwart-v1` intentionally starts
fresh state. The old `manafishrov-stalwart` backend Secrets must remain intact.
Do not migrate/copy old resource state or use `state replace-provider`: the
old provider stored v0.16 resource shapes. The company stack's retained imports
adopt objects whose IDs the migration preserves, including the relay secret.
Confirm IDs and an empty second plan during rehearsal.

Stage artifacts first. Suspend Terraform `manafishrov-stalwart` and its parent
`infrastructure-configs` reconciliation before switching the runner or state
suffix. The normal approval policy remains auto; do not resume it against the
old server or before SCIM restoration/import-ID checks. Follow the company
repo's `apps/stalwart/migration/README.md` for the offline migration and the
reviewed first in-cluster plan. Resume the parents only after both revisions
are compatible. There is no safe independent rollout order while both
controllers are active.

Rollback must restore the old server/store, provider/stack revision and backend
suffix together, with reconciliation suspended. Never use the old state with
the v1 schemas or vice versa. Merely changing the suffix does not restore mail
written since cutover.
