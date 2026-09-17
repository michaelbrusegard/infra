# Shared SMTP edge

Internet SMTP terminates here; Manafish mailboxes, SCIM and JMAP remain on
its private backend. Only port 25 is public. The separate management Service
shares the VIP but allows only flux-system. Submission and IMAP are not proxied.

Recipient acceptance uses an exact-address SQLite positive cache, populated
through certificate-verified LMTP RCPT probes (never DATA). JMAP discovers
candidates; it is not an authoritative membership snapshot. The initial reviewed
inventory is encrypted in infra-secrets. Committed positives survive backend
outages; unverified addresses, including unseen tags, receive 451. Only the
qualified native nonexistent-mailbox response revokes a positive.

Independent native Sieve and SQL guards protect the HTTP recipient hook.
Per-client and global probe budgets bound unverified lookups. A hook-to-SQL
storage failure can still produce 550; the unchanged native binary cannot make
those operations atomic.

## Operations

- The policy/readiness identity and backend reader are separate from the
  off-pod configuration identity. The latter also reads queue metadata.
- Normal operation unsets recovery variables. Initial/recovery access requires
  an explicit ephemeral Secret and loopback port-forward; there is no public
  recovery Service. Remove the Secret before returning to normal mode.
- Console logs use info level. No raw protocol tracing is enabled.
- Backend LMTP must exclude shared-edge traffic from public-client RCPT
  throttles/abuse bans and use a short, nonzero rejection delay. Native numeric
  duration zero is invalid and falls back to the default delay.
- Preserve the PVC and committed recipient database across restarts. A fresh
  database needs successful native verification before becoming Ready.
- Snapshots are scheduled every six hours to Freddo's separate
  `/stalwart/edge-pvc` repository. The retired `/stalwart/pvc` repository and
  historical backups remain untouched.

## Qualification and accepted limitation

Approved executable SHA-256:
`02030a8334e3bc62bae1fa4a9139f498df0a7e105bd97ec5beacfdfa1be8b614`.
The isolated native suite covered guards, SCIM lifecycle, TLS, outage behavior,
durable queue/restart and tagged delivery; focused tests covered client budgets
and backend abuse bans. Offline checks are included in the flake checks.

Resend accepts ordinary verified-domain senders but rejects SMTP `MAIL FROM:<>`.
Consequently, server-generated delivery-failure notifications routed through
Resend can fail. Michael explicitly accepted deferring this issue for cutover;
it is not fixed by changing the visible From header. Do not describe DSN
transport as qualified.
