# Headless Stalwart inbound edge

This directory is intentionally absent from
`gitops/espresso/apps/kustomization.yaml`. It is deploy-inert until the
encrypted Secrets exist and activation is explicitly authorized.

The edge is a minimal Internet-facing MTA, not a third mail server that users
manage:

- The only public or Service-exposed listener is SMTP port 25.
- There is no HTTPS listener, HTTPRoute, WebUI, IMAP, submission, JMAP mail,
  WebDAV, CalDAV, CardDAV, mailbox, or user account surface.
- A plain HTTP management listener binds only to pod loopback for exec health
  probes and the reconciler. There is no Service or network-policy path to it,
  and the built-in web application is disabled.
- Its SMTP greeting identity is explicitly
  `mail.asgard.michaelbrusegard.com`; this does not publish an HTTP endpoint.
- The sole internal account is the reconciler identity on a non-mail domain.
  It is not part of the recipient directory and is never configured in a mail
  client.

The personal and Manafish Stalwart instances remain independent sources of
truth for domains, accounts, credentials, aliases, lists, mail, outbound
relays, and identity providers. The edge polls their management APIs every 60
seconds and writes only recipient addresses and object class into a small
SQLite directory. Password hashes and mailbox data never leave a backend.

Each backend is updated independently in one SQLite transaction. If a poll
fails or produces invalid duplicate addresses, the previous rows for that
backend remain active. A new edge with no successful sync fails closed; it
does not become a catch-all relay or a ready Service endpoint. Once both
sources have synchronized successfully at least once, transient sync failures
retain the last-known rows and do not make the edge unready. Successful
changes invalidate Stalwart's recipient cache, so account and alias changes do
not require edge changes.

Accepted Internet mail is filtered once at the edge using the real sender IP,
then delivered by domain over network-policy-restricted, TLS-wrapped LMTP:

- `michaelbrusegard.com` -> `stalwart-internal.stalwart.svc.cluster.local:24`
- `manafishrov.com` ->
  `stalwart-internal.manafishrov-stalwart.svc.cluster.local:24`

## One-time credentials

`stalwart-edge-env` in
`infra-secrets/gitops/espresso/apps/stalwart-edge` must contain:

- `STALWART_ADMIN_PASSWORD`
- `STALWART_RECOVERY_ADMIN`
- `STALWART_PERSONAL_SYNC_TOKEN`
- `STALWART_MANAFISH_SYNC_TOKEN`

Create one API key on each backend, store its one-time secret in the matching
edge Secret field, and use `Replace` permissions containing only:

- `sysDomainGet`
- `sysDomainQuery`
- `sysAccountGet`
- `sysAccountQuery`
- `sysMailingListGet`
- `sysMailingListQuery`

These keys cannot change backend state and Stalwart API keys cannot log in to
mail or collaboration protocols. Account provisioning after this one-time
setup is hands-off at the edge.

The VolSync repository Secret is
`freddo-restic-stalwart-edge-pvc`. The PVC preserves queue/filter state and the
last-known recipient index; it does not hold user mailboxes.

## Before activation

1. Create the encrypted Secrets and both least-privilege backend API keys.
2. Confirm `10.0.188.13` and `fd7a:115c:a1e0:188::13` are unallocated.
3. Activate and populate the Manafish backend while all existing SMTP, client,
   DNS, router, and personal Stalwart paths remain unchanged.
4. Activate the edge without moving public port 25. Confirm both sync metadata
   rows have a recent successful timestamp and compare the recipient counts
   with each backend.
5. Test known and unknown recipients, aliases, lists, STARTTLS, filtering, and
   each private LMTP route through an isolated path.
6. Move public port 25 and MX only after the full test matrix passes. Keep the
   previous route available for rollback for at least two weeks.

The namespace, RBAC, certificate-reflection, and existing personal Stalwart
changes in this repository are not deploy-inert if pushed. No staged file has
been pushed or applied.
