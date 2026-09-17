# Backend filtering rollout

Local qualification is complete; rollout changes remain inactive staged patches.
Nothing here authorizes a deployment.

## Boundary

The edge retains SMTP/TLS, recipient validation, native SPF/DKIM/DMARC checks,
and its durable queue. Backend Stalwart performs content classification, learning
and Junk placement. No extra filtering daemon or protocol patch is required.

A trusted DATA Sieve script replaces attacker-supplied authentication summaries
with native verdicts. Backend header rules preserve selected authentication
scores. This is **not** native authentication-context forwarding: it cannot
restore the DMARC flag used for contact-based ham trust/learning. Trusted-reply
handling has a different gate and remains enabled. ARC, DKIM2 and original-client
IP/EHLO reputation are not represented by this summary. Native NA tags remain;
score compensation alone is not sufficient where another rule consumes a tag.

Backend trust is enforced together by:

- `MtaStageData.enableSpamFilter` enabled only for `listener == 'edge-lmtp'`,
  false otherwise. Keep authentication required on other SMTP listeners.
- Private TLS LMTP port 24 reachable only from Cilium identity labels
  `io.kubernetes.pod.namespace=stalwart-edge` and `app=stalwart-edge`.
- Exact canonical verdict validation before any mapping or score credit.

Do not substitute a pod CIDR, a fixed pod IP, or a header's claimed sender for
this boundary. Pod addresses change; the native spam-rule context does not expose
the SMTP listener. The listener restriction belongs in the DATA-stage setting.
Preserve the existing narrow LMTP throttle/abuse-ban exclusions and 1ms wait.

Read-only live checks on 2026-09-17 verified TLS and QUIT on backend port 24 from
the edge. From `uptime-kuma`, backend port 465 completed verified TLS while port
24 timed out. No MAIL, RCPT, DATA, account creation or configuration write was
performed. This supports the current network boundary, not an undeployed
filtering configuration.

## Ordered gates

1. Finish isolated qualification using the exact approved deployment binary and
   the production-matching `fixtures/spam-rules-v3.0.1.json` inventory. Include
   malformed verdicts, authenticated bounces, legitimate SPF-failing/DKIM-passing
   forwarding, clean mail, GTUBE and an actual blocked-domain lookup hit.
2. Prepare backend Junk-only behavior while backend filtering is still off:
   convert the existing `BLOCKED_DOMAIN` Reject object to Score 1000 before
   importing it as `stalwart_spam_tag_score`. Preserve its ID and other existing
   Score weights. Keep thresholds 5/0/0 and reject/discard actions absent. Disable
   unusable Pyzor explicitly; keep LLM disabled and contact/reply settings intact.
   Pin rule downloads to the qualified v3.0.1 release, not `releases/latest`, so
   a new release cannot silently introduce another Reject/Discard action. Verify
   all actions again before enabling filtering. The release URL is version-pinned,
   not content-addressed; replacement of an upstream asset remains a trust risk.
3. Deploy the backward-compatible readiness code in its default `legacy` stage.
   It still accepts exactly the existing RCPT script and makes no new API reads.
4. Through an explicitly approved, one-off administrative path, add only
   `sysMtaStageDataGet` and `sysSenderAuthGet` to the existing readiness principal.
   Preserve existing permissions and its API-key scope. Verify reads using the
   actual readiness credential. The configuration writer cannot manage identities;
   do not rerun the empty-store bootstrap or mount writer credentials in the pod.
5. Set `STALWART_EDGE_FILTERING_STAGE=prepare` before creating the DATA script.
   Readiness permits only these transitions: legacy; exact new script installed
   but unbound; script bound with edge filtering on; script bound with it off.
   It never permits filtering off without the bound, exact script and relaxed
   authentication checks.
6. Install and bind the edge verdict script, leaving edge filtering on. Verify
   its runtime operation after a controlled native restart. Then snapshot edge
   queue IDs and wait for every message in that snapshot to leave the queue,
   with backend filtering still off. Old queued messages can contain an
   attacker-written valid `X-Edge-Auth`; enabling the producer does not sanitize
   them. Restarting also closes old SMTP sessions. Inspect queue metadata only,
   not message bodies. The simplest complete drain proof is an unfiltered
   `x:QueuedMessage/query` returning both `ids: []` and `total: 0` after restart;
   use `filtering-stages/queue-empty-request.json`. A first page of results is not
   a complete snapshot. Do not proceed without a complete drain proof.
7. Install the backend rules, then restart the backend with filtering still off
   and verify persisted rules/safety settings. This clears any cached old Reject
   action before activation. Enable filtering only on private LMTP. Verify
   canonical summaries, actual Inbox/Junk placement, no spam rejection/discard,
   and queue drain. Queued mail accepted before the producer was enabled may lack
   a summary; it must receive no fabricated authentication credit.
8. Only after backend qualification, disable edge content filtering. Tighten
   readiness to `STALWART_EDGE_FILTERING_STAGE=backend`, which requires the exact
   bound script and edge filtering off. Repeat restart and delivery checks.

Existing mailbox rules, quotas and recipient changes can still cause delivery
failures; Junk-only spam handling is not a claim that all post-queue failures are
impossible. Resend's null-envelope/DSN limitation remains a separate deferred task.

## Patches and qualification

The personal `filtering-stages/` patches are separate rollout steps:

- `10-readiness-prepare.patch`: enter transitional readiness after the read grant.
- `20-auth-producer.patch`: install/bind the exact native script; keep filtering on.
- `30-disable-edge-filter.patch`: turn content filtering off **after** backend proof.
- `40-final-readiness.patch`: require the final state, only after the TF change.

Company `docs/filtering/stages/` separately prepares Junk-only settings, installs
backend rules, and enables filtering on private LMTP. Do not apply all patches
or both repositories' changes at once. Each stage needs controller completion
and its operational gate; this avoids a readiness rollout outrunning Terraform.

The approved binary passed **21 native stages and 20 deliveries**, including
null-envelope authenticated mail, queued forwarding through both native restarts,
and fresh post-restart Junk placement. Evidence:
`/tmp/stalwart-edge-wdr7djqy/{report,filtering-proof}.json`; a sanitized snapshot is
in company `docs/filtering/qualification.json`. This does not qualify the running
production model or authorize production mail tests.

```sh
python -B -m unittest discover -s gitops/espresso/apps/stalwart-edge -p 'test_*.py'
python -B -m unittest discover -s packages/stalwart-oss -p 'test_edge*.py'
python -B packages/stalwart-oss/edge.py \\
  --binary /path/to/approved/stalwart \\
  --group filtering \\
  --filter-inventory packages/stalwart-oss/fixtures/spam-rules-v3.0.1.json
```

The native command creates an isolated namespace and requires Linux `unshare`,
`ip`, OpenSSL and BIND `named`. It refuses any binary except approved SHA-256
`02030a8334e3bc62bae1fa4a9139f498df0a7e105bd97ec5beacfdfa1be8b614`.

Changing `READINESS_PERMISSIONS` affects future bootstrap only. It never grants an
existing credential permissions. Keep `legacy` until the explicit grant is
verified; an unknown stage fails readiness.
