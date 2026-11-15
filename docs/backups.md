# Backups

Freddo is the backup target for espresso. It runs an append-only restic REST
server for cluster writers and performs local maintenance, pruning, unlocking,
and checks.

## Local Exploration

Run these on freddo. Most commands need `sudo` because repository directories
and password files are intentionally not world-readable.

List repositories, snapshot counts, on-disk size, and latest snapshot time:

```sh
sudo restic-repos
```

Show snapshots for one repository:

```sh
sudo restic-snapshots jellyfin/repo-config
```

List files in the latest snapshot:

```sh
sudo restic-ls jellyfin/repo-config
```

List files in a specific snapshot:

```sh
sudo restic-ls jellyfin/repo-config 5c091684
```

Show repository disk usage, snapshots, latest restore size, and raw stored data:

```sh
sudo restic-stats jellyfin/repo-config
```

Check a single repository:

```sh
sudo restic-check-one jellyfin/repo-config
```

Restore a snapshot into a scratch directory:

```sh
sudo restic-restore-to jellyfin/repo-config /tmp/restore-jellyfin latest
```

## Maintenance

Freddo checks all repositories weekly:

```sh
sudo systemctl start restic-check.service
sudo journalctl -u restic-check.service -n 200 --no-pager
```

Freddo prunes all repositories daily with this retention:

```text
14 daily
8 weekly
12 monthly
3 yearly
```

Run maintenance manually only when needed:

```sh
sudo systemctl start restic-maintenance.service
sudo journalctl -u restic-maintenance.service -n 200 --no-pager
```

## Restore Drill

Restore drills must never write over live PVCs or live databases. Restore into a
scratch directory, scratch PVC, or scratch database only.

### PVC/File Drill

Use a small repository first, such as `pocket-id/pvc` or `navidrome/repo-data`.

```sh
ssh deploy@deploy-freddo
sudo rm -rf /tmp/restore-pocket-id
sudo restic-restore-to pocket-id/pvc /tmp/restore-pocket-id latest
sudo find /tmp/restore-pocket-id -maxdepth 4 -type f | sort | head
sudo rm -rf /tmp/restore-pocket-id
```

Success criteria:

- The restore command exits successfully.
- Expected application files are present under the restore directory.
- `sudo restic-check-one pocket-id/pvc` succeeds afterward.

### Postgres Drill

Restore the latest dump to files first. Then validate the dump without touching
live databases.

```sh
ssh deploy@deploy-freddo
sudo rm -rf /tmp/restore-nextcloud-postgres
sudo restic-restore-to nextcloud/postgres /tmp/restore-nextcloud-postgres latest
sudo find /tmp/restore-nextcloud-postgres -type f | sort
sudo rm -rf /tmp/restore-nextcloud-postgres
```

Success criteria:

- The dump files restore successfully.
- The expected dump artifact is present.
- If doing a deeper drill, copy the dump to a scratch Postgres instance and
  restore into a scratch database, never the live app database.

### Minecraft Drill

Restore one world into a scratch directory and inspect the expected world files.

```sh
ssh deploy@deploy-freddo
sudo rm -rf /tmp/restore-minecraft-vanilla
sudo restic-restore-to minecraft-vanilla/world /tmp/restore-minecraft-vanilla latest
sudo find /tmp/restore-minecraft-vanilla -maxdepth 5 -type f \( -name level.dat -o -name session.lock \) -print
sudo rm -rf /tmp/restore-minecraft-vanilla
```

Success criteria:

- The restore command exits successfully.
- The restored tree contains expected world files such as `level.dat` and
  region data.
- No live Minecraft PVC is mounted or modified.

### Stalwart Drill

Restore `stalwart-data-backup` into a scratch PVC through VolSync, then start
the same image in recovery mode against it. Recovery mode serves only the HTTP
management/JMAP listener, so the copy binds no SMTP, IMAP or queue. Label the pod
`app: restore-drill-stalwart`, never `app: stalwart`, so the production
Services and policies do not select it.

```sh
k() { ssh -o BatchMode=yes deploy-espresso-1 "sudo -n k3s kubectl -n stalwart $*"; }
```

1. Create a 2Gi `openebs-single-replica` PVC `restore-drill-stalwart` and a
   `ReplicationDestination` with `trigger.manual: drill-1`,
   `restic.repository: freddo-restic-mail-stalwart`,
   `destinationPVC: restore-drill-stalwart`, `copyMethod: Direct` and the
   source's `moverSecurityContext` (2000/2000). Wait for
   `status.lastManualSync == drill-1`; the mover log names the snapshot.
2. Create a secret `restore-drill-stalwart` with a random password as
   `DRILL_PASSWORD` and `STALWART_RECOVERY_ADMIN=drill:{PLAIN}<password>`.
   Never reuse a production credential.
3. Add a deny-all `NetworkPolicy` (`policyTypes: [Ingress, Egress]`, no rules)
   for `app: restore-drill-stalwart`. Start a `restartPolicy: Never` pod from
   the production image with `STALWART_RECOVERY_MODE=true`,
   `STALWART_RECOVERY_MODE_PORT=8080`, the secret as `envFrom`, the PVC at
   `/var/lib/stalwart` and the `stalwart-config` ConfigMap at
   `/var/lib/stalwart/config.json`. Startup takes about a minute because OIDC
   discovery times out behind the policy.
4. Query it from inside the pod with
   `curl -u "drill:$DRILL_PASSWORD" http://127.0.0.1:8080/jmap`:
   `x:Account/get`, `x:Domain/get`, `x:NetworkListener/get`,
   `x:DkimSignature/get`, `x:MtaRoute/get`, `x:Directory/get`, then
   `Mailbox/get` and `Email/query` (`calculateTotal`) with each account's
   `accountId`. Compare the settings objects with production using the
   runner's `STALWART_TOKEN`. That key cannot read accounts or mail, so
   compare message counts with what the owner sees in webmail or with the
   `message-ingest` events in the production log.
5. Delete the pod, `ReplicationDestination`, NetworkPolicy, secret and PVC.
   Then confirm that nothing matching `drill` or `volsync-dst` is left in the
   namespace and that the released PV is gone.

Success criteria:

- The mover restores the latest snapshot and the server answers
  `/api/account` with 200.
- Accounts, domains with catch-alls, listeners, DKIM signatures, routes and
  the OIDC directory match production. Mailboxes and message counts match.

Last run 2026-11-15 from snapshot `d0be40f9` (06:20Z): all of the above
matched. The mailbox held 0 messages at that point, so message bodies were not
exercised. Repeat after the cutover.

## Notes

Cluster writers use `retain.within: 100y` so they do not meaningfully prune
append-only repositories. Freddo owns pruning through local maintenance.

Media repositories use names like `repo-config` and `repo-data` instead of raw
`config` or `data` path segments because those names conflict with rest-server
API paths when used directly in REST repository URLs.
