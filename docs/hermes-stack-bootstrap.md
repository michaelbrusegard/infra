# Hermes stack bootstrap

The stack is declarative after these application-issued credentials have been
created once. Keep all resulting values in `infra-secrets`; do not put them in
this repository or shell history.

## 1. Authenticate CLIProxyAPI

The proxy API key and persistent auth PVC are created declaratively. Provider
OAuth sessions must be authorized interactively inside the running pod:

```sh
kubectl -n cliproxyapi exec -it cliproxyapi-0 -- \
  /CLIProxyAPI/CLIProxyAPI -config /config/config.yaml -kimi-login -no-browser
kubectl -n cliproxyapi exec -it cliproxyapi-0 -- \
  /CLIProxyAPI/CLIProxyAPI -config /config/config.yaml -codex-device-login
```

Forward any callback port printed by the command, for example:

```sh
kubectl -n cliproxyapi port-forward pod/cliproxyapi-0 1455:1455
```

Confirm the exposed model IDs before changing the model declarations:

```sh
proxy_key=$(kubectl -n cliproxyapi get secret cliproxyapi -o jsonpath='{.data.API_KEY}' | base64 -d)
curl -fsS -H "Authorization: Bearer $proxy_key" \
  https://llm.asgard.michaelbrusegard.com/v1/models | jq -r '.data[].id'
unset proxy_key
```

Hermes and Hindsight currently use `gpt-5.4` through the OpenAI Codex login.
Kimi can be added later with the login command above, then enabled by changing
the model in both manifests.

## 2. Bootstrap Mattermost

Mattermost Team Edition does not provide generic OIDC, so this instance uses a
local login instead of adding a second proxy/login prompt in front of it. Create
the first local system administrator with username `mattermost_admin` and email
`infra@michaelbrusegard.com`, then create the private `Hermes` team. The initial
rollout keeps the Mattermost OpenTofu object suspended until this bootstrap is
complete so it cannot create duplicate default channels.

With local mode enabled, create an administrator token and the Hermes bot from
inside the running pod:

```sh
kubectl -n mattermost exec -it mattermost-0 -- \
  mmctl token generate mattermost_admin opentofu --local
kubectl -n mattermost exec -it mattermost-0 -- \
  mmctl bot create hermes --display-name Hermes \
  --description "Hermes Agent" --with-token --local
kubectl -n mattermost exec mattermost-0 -- \
  mmctl user search mattermost_admin --json --local
kubectl -n mattermost exec mattermost-0 -- \
  mmctl team search hermes --json --local
kubectl -n mattermost exec mattermost-0 -- \
  mmctl channel search town-square --team hermes --json --local
kubectl -n mattermost exec mattermost-0 -- \
  mmctl channel search off-topic --team hermes --json --local
```

Using `sops`, replace the placeholders in the secrets repository:

- `gitops/espresso/infrastructure/mattermost-tofu/secrets.yaml`:
  `mattermost_admin_username`, `mattermost_admin_token`,
  `mattermost_team_id`, `mattermost_town_square_channel_id`, and
  `mattermost_off_topic_channel_id`;
- `gitops/espresso/apps/mattermost/secrets.yaml`: `HERMES_BOT_TOKEN` and
  `HERMES_ALLOWED_USERS`, where the allowed value is the administrator's
  26-character user ID.

Remove `spec.suspend: true` from the Mattermost Terraform object after replacing
all placeholders. The pinned OpenTofu provider adopts the existing team and its
two default channels, renames Town Square to `assistant` and Off-Topic to
`scratchpad`, creates `meals`, `shopping`, `finance`, `homelab`, and `alerts`,
adds both accounts, and creates the channel-locked Alertmanager webhook. The
generated webhook URL is written to `mattermost-outputs` and reflected only to
the monitoring and Hermes namespaces. The same output secret configures
`assistant` as Hermes' home channel, limits Hermes to the seven managed channels,
and enables mention-free responses everywhere except `alerts`. Team, channel,
and webhook resources all use `prevent_destroy` because the provider otherwise
calls Mattermost's permanent deletion APIs. Unlike the other OpenTofu stacks,
Mattermost plans require explicit approval so a plan that removes messaging
history cannot be applied automatically.

Every post in `scratchpad`, including a reply, receives a unique Hermes session.
The image patch also disables Hindsight, built-in memory, and session search for
that channel, so scratchpad turns neither read nor write persistent conversational
memory. Mattermost still retains the posts and Hermes still retains its session
transcripts for audit; the isolation concerns model context, not message deletion.

Alertmanager posts warning and critical notifications directly to `alerts` and
also calls the authenticated, cluster-internal Hermes webhook for firing alerts.
This triggers the main Hermes instance to perform a read-only-first
investigation and post its findings to `alerts`. It does not create a second
Hermes deployment. Because the main agent has broader cluster permissions and
approvals are disabled, its alert prompt explicitly prohibits automatic
remediation; request any resulting change interactively in Mattermost.

## 3. Bootstrap Mealie API access

Sign in to `https://mealie.asgard.michaelbrusegard.com` through Pocket ID. In
Mealie, create a dedicated non-admin `hermes` user with recipe read/write/import,
meal-plan, and shopping-list permissions. Create an API token from that user's
profile and replace `SET_AFTER_FIRST_LOGIN` in
`../infra-secrets/gitops/espresso/apps/mealie/secrets.yaml`.

Reconcile the secret and restart Hermes. Verify access with an innocuous read
request before allowing recipe writes.

## 4. Finish Honcho retirement

The first rollout retains the `honcho-infra` resources while recording
`drop_cascade = true` for its vector extension. This lets the application
rollout remove every Honcho workload before database destruction begins. After
Honcho pods and jobs are gone, remove the resources from
`gitops/espresso/tofu/honcho/main.tf` for one Flux reconciliation; the cascade
setting lets tofu-controller remove vector-dependent tables, then the database
and role, without orphaning its state. After that empty plan has applied
successfully:

1. remove `gitops/espresso/tofu/honcho/`;
2. remove `gitops/espresso/infrastructure/configs/honcho-tofu/` and its entry
   from the parent kustomization;
3. remove the corresponding encrypted infrastructure secret if one remains.

On Freddo, verify the exact old repository path and then permanently delete it:

```sh
sudo find /srv/backup/honcho -mindepth 1 -maxdepth 2 -type f -name config -printf '%h\n'
sudo rm -rf -- /srv/backup/honcho
```

The deletion is irreversible and intentionally performs no Honcho-to-Hindsight
migration. Hermes' existing `MEMORY.md` and `USER.md` remain on its PVC.

## Image build policy

Hermes is built with `dockerTools` from the upstream pinned Nix package plus an
explicit tool closure. Runtime package managers are rejected by the image smoke
test, and `security.allow_lazy_installs` is disabled. Add future tools to
`packages/hermes-agent-image/default.nix` and rebuild the image instead of
installing them from a running agent.

The shared Postgres image intentionally remains a digest-pinned Dockerfile. It
combines the official Debian PostgreSQL 18 image, version-pinned PGDG extension
packages, and VectorChord's prebuilt PostgreSQL 18 files. Rebuilding that mix on
Nix would cross package/extension ABIs and is not a safe mechanical conversion;
the current Dockerfile is already declarative at the package and image level.
Third-party services continue to use their upstream images rather than locally
repackaging them without a concrete need.
