# AGENTS.md

Personal multi-host Nix flake (NixOS, nix-darwin, Home Manager) plus the
FluxCD-managed k3s cluster `espresso` under `gitops/`. Secrets live in the
private sibling flake `../infra-secrets`, input `secrets`.

## How the Nix code is wired

Every `.nix` file under `modules/` is a flake-parts module and is imported
automatically. A new file needs no registration; a file or folder whose name
starts with `_` is skipped.

- `modules/features/` — one file per feature. It sets
  `flake.modules.<class>.<name>` for each class it supports (`nixos`, `darwin`,
  `homeManager`), so the system and home halves of a feature sit together.
- `modules/bundles/` — named sets of features (`base`, `server`, `desktop`…).
- `modules/hosts/<name>/` — the host's `hosts.<name>` registry entry and its
  module. System outputs, colmena nodes and the CI matrix all derive from the
  registry in `modules/flake/hosts.nix`.
- `modules/users/` — one file per account: system user and Home Manager profile.
- `modules/flake/` — flake-level outputs: formatter, checks, dev shell.
- `packages/`, `overlays/` — plain Nix, not modules.
- `config/` — app state linked out of the store into this checkout. Moving it
  breaks the running desktop until the next switch.

Reference a static file with a relative path literal next to the feature that
uses it.

## Checks

Each failure message says what to fix.

```sh
nix run .#lint     # seconds: format, lint rules, secret scan. Run it often.
nix run .#verify   # under a minute when cached: this system's flake checks and every host.
nix run .#check    # needs network: manifest schemas, tofu validate. For gitops/.
```

Run `verify` before calling a change done, and `check` as well when `gitops/`
changed. `verify` builds the checks for the system it runs on, so the router VM
tests only run on Linux. `nix flake check` covers the same ground one host at a
time and takes more than twice as long.

`verify` evaluates hosts without building them. After changing `flake.lock` by
hand, run `nix run .#update-gate` as well: it builds the x86 servers, which is
where a package that no longer compiles shows up.

`diff-hosts` prints values from host closures, which can include secrets. Pass
`--names-only` anywhere the output is published.

To see what a change does instead of reading its source:

```sh
nix run .#diff-hosts -- main [host...]   # host derivations, ignoring list order
nix run .#diff-manifests -- main         # rendered cluster resources
```

While iterating on one host, evaluate just that one:
`nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run`.

When you are corrected on something a machine could have caught, add the rule
under `lint/rules/` or a script under `gitops/espresso/tests/` in the same
change, and keep prose here for judgment calls. A rule comes with matching and
non-matching snippets under `lint/rule-tests/`, which `lint` runs first.

Comments are banned in Go and Python. In Nix and YAML a comment states a
reason the code cannot show; a `TODO` carries a link.

## Boundaries

- Pushing or merging to `main` deploys `gitops/espresso` through Flux and is a
  production change. Commit freely on the task branch; push, merge and apply
  (`nh`, `colmena`) only when asked.
- Create public GitHub artifacts (issues, PRs, comments, releases) only when
  asked. Reading is fine.
- Anything sensitive goes in `../infra-secrets` through `sops`.
- Adding a host or a cluster app: use the `add-host` and `add-espresso-app`
  skills.

## Commits

Conventional Commits, checked by `nix run .#check-commits -- <range>`. Use a
scope when the change is local to one slice: a platform (`nixos`, `darwin`,
`home`), a host or cluster name, or an area (`flake`, `gitops`, `tofu`,
`helix`). Write a body whenever the reason is not obvious from the subject.
`chore(deps)` is reserved for Renovate; a secrets lock bump is
`chore(flake): bump secrets`.
