---
name: add-host
description: Add a new machine to the flake. Use when asked to add, onboard or bootstrap a host, laptop, server, router or Raspberry Pi.
---

# Add a host

A host is one registry entry plus one module. Everything else (the
`nixosConfigurations` or `darwinConfigurations` output, the colmena node, the
CI matrix) is derived from the registry in `modules/flake/hosts.nix`.

1. **Pick the closest existing host** under `modules/hosts/` and read its
   folder. Done when you can name the bundle from `modules/bundles/` the new
   host imports and the features it adds on top.
2. **Create `modules/hosts/<name>/default.nix`** with the `hosts.<name>` entry
   (`system`, `users`, and `platform` or `deploy` when they apply) and
   `flake.modules.<class>.<name>` importing the bundle, plus `time.timeZone`
   and `system.stateVersion`. Put hardware, disks and networking in sibling
   files that add to the same `flake.modules.<class>.<name>`. Done when
   `nix eval .#ci.hosts --json` lists the host.
3. **Add its secrets** in `../infra-secrets`: `hosts/<name>/default.nix`, and a
   `secrets.yaml` with a creation rule and the host's age key in `.sops.yaml`
   when it has encrypted values. Ask the owner for the host key; never
   generate or guess one. Done when the infra-secrets checks in its
   `AGENTS.md` pass.
4. **Evaluate the host** against the local secrets checkout:
   `nix build .#<attribute> --dry-run --override-input secrets path:../infra-secrets`,
   with `<attribute>` taken from `nix eval .#ci.hosts --json`. Done when it
   evaluates without errors.
5. **Add the install notes** to `README.md` only for what differs from the
   shared install section: disk ids for TPM enrollment, ports, quirks.

The lock still pins the old secrets revision after step 3. Tell the owner the
order: push infra-secrets, then `nix flake update secrets` here.
