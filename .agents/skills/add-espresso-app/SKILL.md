---
name: add-espresso-app
description: Add or scaffold an application on the espresso k3s cluster. Use when asked to deploy, add or host a new app, service or workload under gitops/espresso.
---

# Add an espresso app

Read `gitops/espresso/AGENTS.md` first. Flux applies whatever lands on `main`,
so the work is done when the checks pass locally, not when it is pushed.

1. **Copy the shape of the closest existing app** in `gitops/espresso/apps/`
   (`mealie` for one stateful container with Postgres, `searxng` for a
   stateless one). Done when the new folder has `kustomization.yaml`,
   `namespace.yaml`, a network policy, the workload, `services.yaml`, and
   `httproute.yaml` if it is reachable over HTTP.
2. **Register it** in `gitops/espresso/apps/kustomization.yaml`.
3. **Network policy:** default deny, then allow only the peers the app talks
   to. Done when every `port` in the workload is covered by an explicit rule or
   intentionally closed.
4. **Backup:** add `backup.yaml` for every PVC and database, or add an
   exemption with the reason to `gitops/espresso/tests/app-shape.sh` when the
   data can be rebuilt.
5. **Secrets** go in `../infra-secrets/gitops/espresso/apps/<app>/secrets.yaml`
   through `sops`, never in this repo. Reference them by name here. Done when
   that folder has a `kustomization.yaml` listing `secrets.yaml` and the app is
   registered in `../infra-secrets/gitops/espresso/apps/kustomization.yaml`;
   otherwise Flux never creates the Secret.
6. **External resources** (database role, OIDC client, bucket, DNS other than
   a CNAME) belong to the matching OpenTofu stack in `gitops/espresso/tofu/`.
7. **Check:** `nix run .#check` passes. It renders the manifests, validates
   them against their schemas and runs the scripts in
   `gitops/espresso/tests/`. A failure message names the file to fix.
