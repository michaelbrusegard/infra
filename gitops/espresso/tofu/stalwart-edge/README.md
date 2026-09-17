# Stalwart shared SMTP edge

Static configuration only. This TF stack does not deploy a pod, create
credentials, change DNS, or migrate mail. It uses the audited `tahacodes/stalwart` **0.2.3**
provider and leaves the approved OSS image unchanged.

Only SMTP 25 and private management HTTPS 443 are listeners. SMTP identifies as
`mail.asgard.michaelbrusegard.com`; `mx.manafishrov.com` is a public branded MX
name pointing at the same ingress. Management uses
`https://edge.asgard.michaelbrusegard.com`, covered by the mounted wildcard
certificate. Kubernetes restricts 443 to the Flux runner; there is no public
management route, forwarded-header trust, SMTP AUTH, IMAP, submission, or WebUI.

## Bootstrap and imports

Bootstrap must create only the internal machine domain, the file-backed
certificate, HTTPS listener, machine User/API key and temporary recovery access.
Pass the actual server-assigned IDs, not object names:

| Input | Bootstrap object |
| --- | --- |
| `bootstrap_internal_domain_id` | Domain `system.edge.asgard.michaelbrusegard.com` |
| `bootstrap_certificate_id` | Certificate reading `/var/lib/stalwart/private/tls/tls.crt` and `tls.key` |
| `bootstrap_https_listener_id` | NetworkListener `https`, protocol `http`, `[::]:443`, `useTls=true`, `tlsImplicit=true` |
| `bootstrap_webui_id` | Optional existing disabled Application; null creates one |

The domain must have no aliases, catch-all or directory, no relay permission,
and manual certificate/DKIM/DNS management. `Authentication.directoryId` must be
null. TF disables the internal domain, but that alone does **not** stop native
RCPT resolution of the machine User. The Sieve guard is required.

The default `webui_resource_url` is the image's bundled
`file:///usr/local/share/stalwart/webui.zip`. No `latest` URL or updater action is
used. The Application stays disabled.

Singletons are adopted by the provider's create operation; no singleton ID
inputs are needed. Import blocks adopt the three bootstrap objects, plus the
optional Application. Do not also bootstrap the SMTP listener, routes, hook,
lookup store or script: this stack creates them. The imported domain, certificate
and HTTPS listener have `prevent_destroy` guards.

Inject `STALWART_TOKEN` into the runner. Do not set provider basic-auth variables.
Inject `STALWART_RESEND_API_KEY` into Stalwart, not the runner; TF stores only its
environment-variable name. Bootstrap retains ownership of the machine User and
API key. Use native `User.role = "User"`, API-key-only authentication and:

```json
{"@type":"Replace","enabledPermissions":{"PERMISSION":true},"disabledPermissions":{}}
```

Replace `PERMISSION` with every member of `bootstrap-permissions.json`.
Bootstrap and `outputs.tf` both read that canonical configuration-writer list. It includes `authenticate`, `sysActionCreate`, `actionReloadSettings`,
`actionReloadTlsCertificates`; Get/Update for the listed singleton/imported types; and Get/Create/Update/Destroy
for the managed collections. Queue Query/Get permits operational inspection;
console-tracer permissions permit info logging. It includes no Action/Get,
Account, User, Role, API-key management, mailbox access or mail-delivery permissions. NativeReader
uses a separate identity and is not managed here. Remove temporary recovery
credentials after qualification; do not retain a human administrator.

## Acceptance and delivery

`../../apps/stalwart-edge/policy.sql` is the sole SQL source. Both the policy
service and TF consume it. `StoreLookup` uses SQLite at
`/var/lib/stalwart/routing/recipients.sqlite3`. The query binds `[rcpt]` to `?1`
and returns one integer from `SELECT EXISTS`, compared explicitly with `1`.
The expression embeds the query as a raw double-quoted multiline string, not
`jsonencode(query)`: the native expression parser does not decode JSON Unicode
escapes. A precondition forbids double quotes/backslashes in the SQL source.
Only exact `manafishrov.com` reaches the lookup; every other domain gets false.
Do not create a native Domain, Directory, Account or MailingList for a served
domain: UnknownDomain must enter the relay predicate, never SQL Directory
account auto-provisioning. The internal machine domain is the only Domain here.

The RCPT hook calls `http://127.0.0.1:8090/rcpt`, times out after five seconds and
temporarily fails on errors. It must never modify the envelope. A separate,
I/O-free trusted RCPT Sieve rejects every unapproved domain, including the
machine domain. No recipient rewriting is configured.

Both defenses must be present and loaded. If the hook is missing, the guard
still rejects outside domains; if the script is missing, the hook must reject
them. Missing both is **not** safe: native machine-User resolution can accept
before the relay predicate, regardless of domain enabled/emailReceive flags.
The parent readiness checks must test both missing-defense cases and actual
SMTP behavior, not just registry objects.

Exact `manafishrov.com` routes only to certificate-verified implicit-TLS LMTP at
`backend.manafishrov.com:24`. There is no local or Internet MX fallback. Other
queued destinations (edge-generated DSNs) use verified implicit-TLS SMTP at
`smtp.resend.com:465`, username `resend` and the environment secret above.
`stalwart_dsn_report_settings.edge.from_address` maps to native
`DsnReportSettings.fromAddress` and sets the **From header** to
`postmaster@manafishrov.com`. Native DSNs still use an empty envelope sender;
Resend rejects that empty envelope sender. Michael accepted deferring this
limitation for cutover; DSN transport is not qualified.

Keep the persistent queue and backups throughout cutover. Backend failure must
leave accepted mail queued, never trigger a queue reset or local delivery.
The parent owns paused-backend and recovery tests. SPF, DKIM, DMARC and reverse
IP checks use relaxed verification; spam filtering remains enabled on port 25.

## Provider and runtime limits

- Settings writes automatically call `x:Action/set` with `ReloadSettings`.
  `sysActionCreate` and `actionReloadSettings` authorize that call. Certificate
  updates instead request `ReloadTlsCertificates`, requiring
  `actionReloadTlsCertificates` too. The provider does not read or query the
  Action. Resource reads use explicit state/import IDs.
- Reload failure is only a provider **warning**. A successful apply is not proof
  of loaded behavior. Reload parses listeners/acceptors but does not bind new
  sockets or stop old accept loops. The parent must perform a controlled first
  restart after configuration and requalify subsequent listener changes.
- `StoreLookup` is also assigned `ReloadSettings` by provider 0.2.3, not
  `ReloadLookupStores`. Do not assume its live connection pool was replaced;
  the controlled restart/readiness checks must prove it uses the intended DB.
- Nullable Optional+Computed fields cannot reliably express clearing an
  existing directory/catch-all. Bootstrap must supply clean null fields. TF
  postconditions reject a non-null global directory or internal catch-all.
- Managing a resource does not purge unmanaged listeners, hooks, routes or
  domains. This stack assumes a clean minimal bootstrap. Inventory/readiness
  must reject unexpected objects before opening ingress.
- Policy schema v2 uses a persistent cache of exact full addresses positively
  verified through certificate-verified backend LMTP RCPT (never DATA). JMAP
  enumeration is discovery only, not an atomic snapshot requirement. Do not
  infer plus-address or alias acceptance or expire positives by TTL. The hook
  must commit each new positive before accepting it, and refuse until source
  seeds are ready. The policy process also requires
  `STALWART_EDGE_POLICY_INVENTORY` pointing to operator JSON
  `{source_name: [expected_full_addresses, ...]}` with nonempty coverage for
  each served domain, and `STALWART_EDGE_POLICY_QUALIFIED=1` attesting actual
  native recipient-policy sender independence. Set that attestation only after
  qualification, never merely because TF validates. Seed completion requires
  complete discovery pagination and individual LMTP verification of expected
  positives; it does not claim an atomic inventory snapshot. Discovery omission
  never revokes a positive; only the source-exact native response
  `550 5.1.2 Mailbox does not exist.` permits revocation. Partial discovery cannot
  establish the initial seed. Existing seed markers survive outages/restarts.
  Native SQL membership does not replace hook/readiness seed checks. A SQL error after
  hook acceptance may still yield native 550 rather than 451. The parent owns
  these runtime inputs and native qualification; TF does not set the attestation.

## Kubernetes integration

The app and `infrastructure/configs/stalwart-edge-tofu` are included in the root
Kustomizations following native qualification. The active Terraform resource
derives from the personal `tofu-base`, not the Manafish base, and adopts the
bootstrapped state. The runner is pinned to Linux amd64 to
match the audited provider lock; its mirror initializer verifies the same
provider archive SHA-256 used locally, without installing a runtime CLI.

The single 20Gi data PVC is unchanged. The main container uses the approved
`sha-f5918b808ac9f481f63deeeb8a9c0a526faf57a5-670b02fc450a` image with digest
`ee91efd83fd1c4ab51d1462e7b0188546449093e7960ead09f4917c068dbbd2d`.
The Python policy image is pinned independently; no `apk`, downloaded CLI,
permanent recovery administrator or shared process namespace is used. The pod
has no service-account token. The policy container sees the data volume
read-only except for its routing subdirectory.

The parent owns bootstrap and `/policy/readiness.py`. Readiness checks both
native registry attachments and actual TLS SMTP rejection of outside/machine
recipients. The main probe also requires `/var/lib/stalwart/.bootstrapped` and
verified HTTPS health with the edge hostname/SNI over loopback. Before the
marker exists, startup/liveness use loopback recovery HTTP only when the
optional ephemeral recovery secret is present. Port 8080 has no Service or CNP
allowance. The normal entrypoint unsets every recovery variable even if the
optional secret was accidentally retained. Parent bootstrap creates the
marker, controls the restart and deletes the ephemeral secret afterward.

Secret wiring is explicit; the obsolete broad `stalwart-edge-env` is unused:

| Namespace | Secret | Keys / consumer |
| --- | --- | --- |
| `stalwart-edge` | `stalwart-edge-resend` | `api-key` -> main `STALWART_RESEND_API_KEY` |
| `stalwart-edge` | `stalwart-edge-bootstrap` (optional, ephemeral) | `STALWART_RECOVERY_ADMIN` -> initial main only |
| `stalwart-edge` | `stalwart-edge-reader` | `token` -> policy `STALWART_MANAFISH_SYNC_TOKEN` |
| `stalwart-edge` | `stalwart-edge-readiness` | `token` -> probe `STALWART_EDGE_READINESS_TOKEN` |
| `flux-system` | `stalwart-edge-tofu` | `STALWART_TOKEN`, `TF_VAR_bootstrap_internal_domain_id`, `TF_VAR_bootstrap_certificate_id`, `TF_VAR_bootstrap_https_listener_id`; optional `TF_VAR_bootstrap_webui_id` -> runner only |

The runtime ConfigMap contains qualification `1` after native acceptance tests.
The reviewed inventory comes from encrypted Secret `stalwart-edge-inventory`,
mounted at `/policy-inventory/inventory.json`; it is not public ConfigMap data.
Bootstrap uses separate internal Users `tofu` and `readiness`. The readonly
readiness identity's permissions come from the parent script, not the writer
permission list. No writer token enters the mail pod.

SMTP and management are separate LoadBalancer Services sharing staging VIPs
`10.0.188.13` / `fd7a:115c:a1e0:188::13`. SMTP is Ready-only; management publishes
unready endpoints so failed configuration can still be repaired. Both use
`lbipam.cilium.io/sharing-key: stalwart-edge`, `externalTrafficPolicy: Local`
and the same selector. Cilium v1.20.0 requires matching traffic policies and,
for Local, selectors (verified in `operator/pkg/lbipam/service_store.go`). Ports
25 and 443 do not overlap. Moving to `.12` is a separate cutover.

Only management carries the internal k8s-gateway hostname annotation. The
external-dns controller has `sources: [crd]`, so this does not publish a public
record. There is no HTTPRoute or DNSEndpoint here. The CNP admits management
only from `flux-system`; same-pod readiness uses loopback. Egress permits cluster
DNS, the Manafish backend on 24/443 and Resend on 465. SPF/DKIM/DMARC/default
DNSBL use DNS; no blanket world 25/80/443 egress is granted. Any future HTTP spam
lookup needs its own reviewed destination rule.

## Offline validation

No remote backend initialization, plan, apply or live API calls are needed:

```sh
export TF_CLI_CONFIG_FILE=/tmp/mail-direct-cutover/tofurc
tofu -chdir=gitops/espresso/tofu/stalwart-edge fmt -check
tofu -chdir=gitops/espresso/tofu/stalwart-edge init -backend=false -input=false
tofu -chdir=gitops/espresso/tofu/stalwart-edge validate
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover \
  -s gitops/espresso/tofu/stalwart-edge -p 'test_*.py'
```

The Kubernetes backend declaration is empty so tofu-controller can supply its
normal namespace/state-secret configuration from the root TF base. The local
mirror lock contains the audited Linux amd64 package hash only. Do not switch
provider versions or fetch dependencies to extend this stack.

Source checks used the pinned native source
`/nix/store/v3qv3j0ylywrg5znd68flzmkxfm3zlk6-source` (registry schema,
`common/src/expr/functions/asynch.rs`, `common/src/cache/reload.rs`) and provider
v0.2.3 (`internal/provider/generic_resource.go`, generated descriptors,
`internal/client/client.go`). Schema validation does not replace the parent's
isolated normal-mode native fixture and loaded-behavior readiness tests.
