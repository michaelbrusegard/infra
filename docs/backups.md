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

## Notes

Cluster writers use `retain.within: 100y` so they do not meaningfully prune
append-only repositories. Freddo owns pruning through local maintenance.

Media repositories use names like `repo-config` and `repo-data` instead of raw
`config` or `data` path segments because those names conflict with rest-server
API paths when used directly in REST repository URLs.
