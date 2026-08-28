# AGENTS.md

## Purpose

Personal multi-host Nix flake. Manages NixOS, nix-darwin, and Home Manager,
plus a FluxCD-managed Kubernetes cluster (`espresso`) under `gitops/`. Pairs
with the private sibling flake `../infra-secrets` exposed as input `secrets`.

## Hosts

| Host               | Type          | Apply                           |
| ------------------ | ------------- | ------------------------------- |
| `lungo`            | nix-darwin    | `nh darwin switch`              |
| `ristretto`        | NixOS desktop | `nh os switch`                  |
| `forte`            | NixOS laptop  | `nh os switch`                  |
| `ristretto-wsl`    | NixOS WSL     | `nh os switch`                  |
| `macchiato`        | NixOS router  | `colmena apply --on macchiato`  |
| `cortado`          | NixOS router  | `colmena apply --on cortado`    |
| `leggero`          | NixOS RPi     | `colmena apply --on leggero`    |
| `espresso-{0,1,2}` | NixOS k3s     | `colmena apply --on espresso-*` |

`programs.nh` is wired to this flake on every system, so `nh` works without
flags. First-time bare-metal installs use `nixos-anywhere` — see `README.md`.

`gitops/espresso/` is reconciled by FluxCD on push to `main`. Pushing is
deploying — only push when the change is meant to roll out.

## Structure

- `flake.nix` — inputs, outputs, host wiring
- `lib/` — flake helpers (`mkSystem`, `mkCluster`, `mkNode`)
- `hosts/<name>/` — per-machine config
- `modules/{common,nixos,darwin,home}/` — reusable modules, split by platform
- `users/{michaelbrusegard,admin,deploy}/` — accounts + Home Manager profiles
- `packages/`, `overlays/` — custom packages and overlay composition
- `gitops/espresso/` — FluxCD + Kustomize + OpenTofu state for the k3s cluster
- `config/` — static app configs consumed by Home Manager
- `windows/` — Windows-side dotfiles

### Cloudflare DNS

Two declarative systems, split by record type — keep new records on the right
side:

- **OpenTofu** (`gitops/espresso/tofu/dns`, cloudflare provider) — static
  infrastructure records: MX, TXT, DKIM, MTA-STS, and anything external-dns
  can't express. Reconciled by tofu-controller.
- **external-dns** (`DNSEndpoint` CRDs, `managedRecordTypes: [CNAME]`) — dynamic
  per-service CNAMEs that point at `router.asgard.michaelbrusegard.com` (the
  macchiato WAN dyndns A record). Zones it manages are listed in
  `infrastructure/controllers/external-dns` `domainFilters`; add the zone there
  before adding records for a new domain.

## Commands

### Tooling

`.envrc` runs `use flake`, so direnv auto-loads the dev shell on `cd` into
the repo. Without direnv, run `nix develop`. Either way you get `age`, `sops`,
`kubectl`, `kustomize`, `fluxcd`, `opentofu`, `gh`, `jq`, `yq-go`.

### Quality

```sh
nix fmt                     # treefmt: alejandra + statix + deadnix
nix flake check --show-trace
```

### Validate without applying

```sh
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run
nix build .#darwinConfigurations.lungo.system --dry-run
colmena build --on <node>
```

When touching `gitops/`:

```sh
kustomize build gitops/espresso | kubeconform -strict -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

When touching `*.tf` under `gitops/espresso/tofu/<stack>`:

```sh
tofu -chdir=gitops/espresso/tofu/<stack> fmt -check
tofu -chdir=gitops/espresso/tofu/<stack> init -backend=false
tofu -chdir=gitops/espresso/tofu/<stack> validate
```

### Sibling secrets repo

```sh
nix run .#fmt-infra-secrets    # treefmt on ../infra-secrets
nix run .#lint-infra-secrets   # treefmt + statix + deadnix on ../infra-secrets
```

Pull in new commits from the secrets flake (after they land on its `main`):

```sh
nix flake update secrets   # bumps just the secrets input in flake.lock
```

Commit the resulting `flake.lock` change as `chore(flake): bump secrets`
(or describe the _why_ if it's tied to a specific feature).

## Rules

- Run `nix fmt` and `nix flake check --show-trace` before considering a change
  done.
- Match existing module style; modules are split by platform under `modules/`.
- Don't add dependencies without a clear reason.
- Anything sensitive belongs in `../infra-secrets`. Never write plaintext
  secrets here.
- Commit freely; **never push without being asked**. Pushes to `main` trigger
  CI for the whole flake and roll out `gitops/espresso/` to the cluster via
  FluxCD.
- **Never create public GitHub artifacts without being asked.** This covers
  issues, pull requests, comments, releases, gists, and discussions on any
  repo — mine or third-party. Read operations (`gh api …`, `gh issue list`,
  `gh pr view`, fetching docs) are fine.

## Commits

Follow Conventional Commits strictly. Improve on past history where it was
loose.

Format:

```
<type>(<scope>): <subject>

[optional body explaining *why*, wrapped ~72 chars]
```

- **Subject**: imperative, lowercase, ≤72 chars, no trailing period.
- **Body**: include one whenever the _why_ isn't obvious from the subject. The
  diff already shows the _what_.
- **Types**: `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`, `ci`, `build`,
  `revert`. `chore(deps)` is reserved for Renovate.
- **Scope**: prefer one whenever the change is local to a slice. Common scopes:
  - Platform: `darwin`, `nixos`, `home`, `common`
  - Host/cluster: `lungo`, `ristretto`, `forte`, `macchiato`, `leggero`, `espresso`
  - Area: `flake`, `lib`, `gitops`, `tofu`, `cli`, `neovim`, `hyprland`

Good:

- `feat(darwin): switch to aerospace for tiling`
- `fix(nh): correct double-gc configuration on darwin`
- `refactor(home): split cli modules by user scope`
- `feat(espresso): add tofu-controller credentials`
- `chore(flake): bump secrets`

Bad:

- `update flake.nix`
- `fix bug`
- `feat: stuff` (missing scope and why)

Commit freely. Don't push unless explicitly asked.

## Keep this file useful

If you add a host, change directory layout, change apply commands, or alter
formatting/lint tooling — update this file in the same commit.
