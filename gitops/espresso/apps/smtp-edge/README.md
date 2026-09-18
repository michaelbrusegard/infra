# Postfix SMTP edge

Public SMTP/25 routes `manafishrov.com` through a durable Postfix queue to the
Manafishrov Stalwart backend. Stalwart owns mailboxes, native authentication,
spam classification and learning. The edge has no management credentials,
recipient-inventory service, SQL cache, Sieve bridge or custom readiness writer.

- VIPs: `10.0.188.12`, `fd7a:115c:a1e0:188::12`; MX/router DDNS unchanged.
- `externalTrafficPolicy: Local` preserves the peer address.
- Recipient verification uses certificate-verified implicit-TLS LMTP/24,
  stopping at RCPT without submitting a probe message.
- Protected Postfix queue IP/EHLO attributes go through `pipe(8)` and curl to
  verified STARTTLS/25 with PROXY. Generated mail without a client IP uses
  STARTTLS/26 without PROXY, authentication checks or spam filtering.
- Backend Cilium policy requires both namespace `smtp-edge` and app `smtp-edge`.
  Pod CIDRs select PROXY parsing; they are not the authorization boundary.
- No AUTH or external relay on the public listener. Only SMTP/25 is exposed.
  The existing Resend relay remains implicit TLS/465; external null-envelope
  DSNs remain unsupported by Resend. Do not rewrite null senders to hide this.

## Recipient and filtering semantics

Native positive verification is optimistic for one hour. A pending probe can
extend expiration by the remaining native 1000-second grace; a negative refresh
does not revoke an unexpired positive. Unseen/expired recipients defer during
outages outside that grace. This is not immediate recipient revocation.

Native domain sub-addressing is Disabled for `manafishrov.com`: undefined plus
addresses are rejected, explicitly configured plus aliases still work. Before
changing this policy, old acceptance was quiesced, sessions closed, and complete
old-edge/backend queues drained while implicit plus resolution remained Enabled.

Sender checks are relaxed and filtering is Junk-only (spam 5, reject/discard 0).
BLOCKED_DOMAIN was converted in place to Score 1000 before activation. Contact
and reply trust remain enabled. No authentication-score overrides are installed.
Stock mail-auth returns DMARC none when neither SPF nor DKIM passes; real failing
alignment is tested separately. Incoming headers are preserved, not trusted as
the authentication context.

## Queue backup and recovery

The retained `data-smtp-edge-0` PVC holds the spool and verification cache.
PID locks live on an emptyDir, not the PVC. Freddo repository
`/stalwart/smtp-edge-pvc` is separate from both historical Stalwart repositories.

The source mover runs as queue UID/GID 100 **without fsGroup**. Recursive fsGroup
chmod changes bits Postfix uses as queue flags. A restore into a **fresh, empty**
PVC may use UID/GID/fsGroup 100 so the mover can write; do not apply fsGroup to an
existing/restored queue or the Postfix pod. Restic writes the original file modes,
and the entrypoint restores mixed directory ownership without changing queue-file
flags. TLS and relay credentials come from Secrets, not the queue backup.

Start a restored spool isolated from delivery. Compare complete queue metadata
and account for mail delivered since the snapshot before allowing egress. Native
Postfix may rename short queue IDs to match restored inode numbers. Snapshot
recovery can redeliver already delivered mail; there is no exactly-once claim.

Live recovery of snapshot `93ee1e08` preserved the held queue file byte-for-byte,
including hold/expiry state and protected attributes. The recovered synthetic
message reached native Junk before its original held duplicate was removed.
Earlier trial snapshots are not qualified recovery points. The retired edge PVC
and `/stalwart/edge-pvc` history remain protected in `../stalwart-edge`.

## Validation and operations

`packages/smtp-edge/qualification.json` records 19 native stages, 15 deliveries,
the approved Stalwart binary, source hashes and the actual Docker config digest.
The publication workflow hashes archive config JSON rather than Docker `.Id`,
whose meaning differs with Docker 29's containerd store. Registry manifests are
pinned separately in `statefulset.yaml`.

Live checks covered TLS, recipient verification, relay denial, both wrong-app
and wrong-namespace Cilium denials, pod restart, cold-cache backup, clean restore,
queue-file identity and native Junk ingestion. Readiness is native Postfix status;
a backend outage is buffered by the queue, not hidden by a management probe.

```sh
kubectl --context=espresso -n smtp-edge exec smtp-edge-0 -- postqueue -j
kubectl --context=espresso -n smtp-edge get replicationsource smtp-edge-data-backup
```
