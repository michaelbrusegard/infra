# SMTP edge staging

Routing-only Postfix for `manafishrov.com`. This directory is deliberately absent
from the apps root kustomization. Replicas are zero, both Services are internal,
world ingress is denied, and the new backup is paused. Nothing here claims the
existing VIPs `10.0.188.12` / `fd7a:115c:a1e0:188::12`.

The image owns its configuration and delivery adapter in `packages/smtp-edge/`.
There is no Python service, recipient inventory, API/JMAP credential, management
port, AUTH listener, readiness writer or second configuration writer.

## Routing and isolation

- Public SMTP will use port 25 only, with opportunistic inbound STARTTLS and no
  AUTH. Recipient verification uses certificate-verified private TLS LMTP on backend
  port 24. No open relay or edge mailbox delivery is intended.
- Queued Internet messages go to `backend.manafishrov.com:25` with required
  STARTTLS and the original queued client IP in PROXY. Locally generated mail
  for the served domain goes to the separate STARTTLS listener on port 26.
  Stalwart owns authentication, DMARC and filtering.
- Cilium permits backend ports 24/25/26 only to pods with namespace
  `manafishrov-stalwart` and app `stalwart`. There is no backend FQDN fallback.
  The private DNS name must resolve to that Service and preserve this identity.
  DNS is allowed only to cluster DNS; external egress is only Resend implicit TLS port 465.
- Root Postfix master needs exactly CHOWN, SETUID, SETGID, DAC_OVERRIDE, FOWNER,
  KILL and NET_BIND_SERVICE. It drops privileges to image-defined IDs 100/101/102.
  The root filesystem is read-only; `/run`, `/tmp` and `/var/lib/postfix` are
  writable. Do not add an fsGroup or recursively flatten queue ownership.
  Production uses RuntimeDefault seccomp, never the fixture's unconfined mode.
- Startup/readiness run `postfix check && postfix status` against the existing
  runtime configuration. Native check may repair missing queue directories; it
  does not regenerate credential maps like the entrypoint's `check` mode.
  These checks neither submit mail nor depend on backend availability. They
  indicate local daemon/configuration health, not end-to-end acceptance.
  There is no backend-triggered liveness restart loop.

## Gates before enabling

1. **Preserve the known Resend limitation.** The image uses certificate-verified
   implicit TLS on 465. Resend rejects `MAIL FROM:<>`; the earlier cutover
   explicitly deferred external DSN delivery. Postfix does not fix that provider
   limitation or rewrite null senders. Local-domain DSNs use backend port 26 and
   are qualified separately.
2. **Publish only with explicit authorization.** The dispatch-only
   `.github/workflows/smtp-edge-image.yaml` requires `authorize_publish=true`.
   It builds the locked public Nix package without the private secrets flake,
   exports the image, publishes a source/archive-specific tag and records the
   registry manifest digest. It does not update manifests or deploy. The
   current `pending-immutable-pin` tag is a deliberate placeholder, not a release.
   Replace it with `ghcr.io/michaelbrusegard/smtp-edge@sha256:<registry digest>`
   after qualifying the published artifact. Docker config ID
   `sha256:5ef910d682ff9aabb1da23b8896eedaf023d1dbc1c95019abab6fea605d6c7f3`
   is NOT an OCI registry digest and must not be used as the production pin.
3. **Provision parent-owned secrets.** Reflect the existing wildcard certificate
   into `smtp-edge/wildcard-tls` (`tls.crt`, `tls.key`) by updating the source
   certificate's reflector namespace allowlist. Copy the SOPS-managed Resend
   credential to `smtp-edge/smtp-edge-resend`, key `api-key`. Both mounts are
   read-only and mode 0400, with no fsGroup. `RESEND_PASSWORD_FILE` points to the
   mounted file; the credential is not an environment value. No secret contents
   or new reflector source are defined here. Confirm GHCR pull visibility or
   provision an approved imagePullSecret before starting.
4. **Qualify the actual Kubernetes security/storage path.** Parent-supplied native
   evidence at `/tmp/smtp-edge-postfix-w7ckwaab/report.json` reports 19 passing
   native stages and 15 deliveries through Postfix 3.11.3/curl 8.20. Postfix uses
   default seccomp, no-new-privileges, exact capabilities and root-owned 0400 TLS
   mounts; only the separate native fixture helper uses unconfined seccomp.
   Kubernetes networking/storage and external Resend DSNs remain unqualified.
   Check the published image with live dual-stack backend resolution,
   reflected TLS, restart/recovery and Cilium identity enforcement. Confirm the
   finite verification-cache behavior is acceptable: positives expire after one
   hour, but a pending probe extends acceptance for its fixed 1000-second grace.
   Failed refreshes, including authoritative negatives, do not revoke an
   unexpired positive. Unseen recipients defer during outages; expired positives
   defer once outside that pending-probe grace. Backend domain sub-addressing
   must be disabled so only explicitly configured plus aliases are accepted.
5. **Prepare backup and cutover.** Provision the new backup repository below,
   authorize root integration and an internal one-replica trial, then verify a
   snapshot/restore. Independently validate SMTP behavior; readiness alone is
   not approval. Transfer the old VIPs only in the parent's coordinated cutover.
   The future public Service must retain source IPs (`externalTrafficPolicy:
   Local`), publish only ready endpoints, expose only port 25, and add only
   world-to-25 ingress to this policy. Keep the headless Service internal. Do not
   expose ports 24/26, submission/AUTH, or management on the public edge.

## Queue, mail and backups

`data-smtp-edge-0` is a new 20Gi `ssd-ha` PVC containing all of `/var/lib/postfix`,
including queue and recipient verification cache. StatefulSet scale-down and
removal retain it. Do not mount the old Stalwart PVC into Postfix: their queue
formats are incompatible. Postfix's configured queue lifetime remains five days.

Before backend activation disables domain-wide sub-addressing, inventory the
complete old-edge and backend queues using envelope metadata only. Drain any
implicit-plus recipients while sub-addressing is still enabled, or explicitly
preserve and verify their destinations. Quiesce old SMTP acceptance and finish
existing sessions if needed to exclude a race. This precedes activation, not
just the final VIP transfer.

Keep the old `data-stalwart-edge-0`, its mail, queue, routing data and existing
ReplicationSource/repository intact. Keep the retired `/stalwart/pvc` repository
as well. Drain the old queue with its own daemon after directing new ingress to
Postfix; do not copy queue files or delete the old namespace/PVC as part of
cutover. Rollback must also account for mail queued on Postfix, without allowing
two daemons to write the same volume or replaying already delivered mail.

The new paused ReplicationSource snapshots `data-smtp-edge-0` every six hours
with the existing Mayastor/VolSync pattern and 14 daily, 8 weekly and 12 monthly
retention. Parent must provision `freddo-restic-smtp-edge-pvc` in this namespace
with a dedicated `/stalwart/smtp-edge-pvc` repository under the existing `stalwart`
backup identity (Freddo enforces private repository prefixes);
never point its pruning at a historical Stalwart repository. Unpause only once
the PVC and repository exist. The root backup mover preserves mixed queue file
ownership and does not match the app's Cilium selector. Existing controller
backup-network policy still needs verification in the new namespace.

Snapshots are crash-consistent, not a guarantee against SMTP replay. Restore to
an isolated PVC without public ingress, preserve owners/modes, inspect the queue
and coordinate delivery before resuming. Test restore and certificate/credential
reprovisioning: `/run` is intentionally ephemeral and credentials are not backed
up with the queue.

## Local checks

```sh
kustomize build gitops/espresso/apps/smtp-edge
```

Keep validation offline and scoped while parent-owned files are changing. Full
flake checks, published-image qualification and live cluster acceptance remain
parent gates; do not invoke the workflow, apply resources or send test mail as
part of staging.
