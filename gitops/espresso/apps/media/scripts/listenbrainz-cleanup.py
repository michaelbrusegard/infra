#!/usr/bin/env python3
import os
import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path

MUSIC_ROOT = Path(os.environ.get("MUSIC_ROOT", "/music"))
STATE_DB = Path(os.environ.get("STATE_DB", "/state/listenbrainz-bridge.db"))
NAVIDROME_DB = Path(os.environ.get("NAVIDROME_DB", "/navidrome/navidrome.db"))
CLEANUP_AFTER_DAYS = int(os.environ.get("CLEANUP_AFTER_DAYS", "30"))


def now():
    return datetime.now(UTC).replace(microsecond=0)


def parse_time(value):
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def log(message):
    print(message, flush=True)


def bridge_db():
    conn = sqlite3.connect(STATE_DB)
    conn.row_factory = sqlite3.Row
    return conn


def navidrome_db():
    conn = sqlite3.connect(f"file:{NAVIDROME_DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def relative_music_path(path):
    return str(path.relative_to(MUSIC_ROOT))


def safe_music_path(path):
    try:
        real = path.resolve()
        real.relative_to((MUSIC_ROOT / "Albums").resolve())
        return True
    except ValueError:
        pass
    try:
        real = path.resolve()
        real.relative_to((MUSIC_ROOT / "Singles").resolve())
        return True
    except ValueError:
        return False


def protected_by_playlist(path):
    """Report whether any playlist lists the file.

    This includes the ListenBrainz playlists: the bridge downloads whatever
    they list, so deleting a listed file would only trigger a redownload.
    """
    rel = relative_music_path(path)
    absolute = str(path)
    playlist_root = MUSIC_ROOT / "Playlists"
    if not playlist_root.exists():
        return False
    for playlist in playlist_root.glob("*.m3u"):
        try:
            text = playlist.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if rel in text or absolute in text or f"../{rel}" in text:
            return True
    return False


def play_state(nav_conn, path):
    rel = relative_music_path(path)
    return nav_conn.execute(
        """
        select coalesce(a.play_count, 0) as play_count,
               coalesce(a.starred, 0) as starred
          from media_file mf
          left join annotation a
            on a.item_id = mf.id and a.item_type = 'media_file'
         where mf.path = ?
         limit 1
        """,
        (rel,),
    ).fetchone()


def prune_empty_dirs(path):
    stop_roots = {(MUSIC_ROOT / "Albums").resolve(), (MUSIC_ROOT / "Singles").resolve()}
    current = path.parent
    while current.exists() and current.resolve() not in stop_roots:
        try:
            current.rmdir()
        except OSError:
            break
        current = current.parent


def main():
    if not STATE_DB.exists():
        log("state DB does not exist; nothing to clean")
        return 0
    bridge = bridge_db()
    nav = navidrome_db()
    run_id = bridge.execute(
        "insert into runs(kind, started_at) values ('cleanup', ?) returning id",
        (now().isoformat(),),
    ).fetchone()[0]
    cutoff = now() - timedelta(days=CLEANUP_AFTER_DAYS)
    deleted = failed = skipped = 0
    rows = bridge.execute(
        """
        select *
          from recommendation_seen
         where status in ('downloaded', 'lossy_fallback')
           and queued_at is not null
           and downloaded_at is not null
           and local_path is not null
        """
    ).fetchall()
    for row in rows:
        path = Path(row["local_path"])
        downloaded_at = parse_time(row["downloaded_at"])
        if not downloaded_at or downloaded_at > cutoff:
            skipped += 1
            continue
        if not path.exists():
            bridge.execute(
                "update recommendation_seen set status = 'deleted', last_error = 'file already missing' where id = ?",
                (row["id"],),
            )
            deleted += 1
            continue
        if not safe_music_path(path):
            skipped += 1
            continue
        state = play_state(nav, path)
        if state is None or state["play_count"] != 0 or state["starred"]:
            skipped += 1
            continue
        if protected_by_playlist(path):
            skipped += 1
            continue
        shared = bridge.execute(
            """
            select count(*) as count
              from recommendation_seen
             where local_path = ?
               and id <> ?
               and status <> 'deleted'
            """,
            (str(path), row["id"]),
        ).fetchone()["count"]
        if shared:
            skipped += 1
            continue
        try:
            path.unlink()
            prune_empty_dirs(path)
            bridge.execute(
                "update recommendation_seen set status = 'deleted', last_error = null where id = ?",
                (row["id"],),
            )
            deleted += 1
            log(f"deleted {path}")
        except OSError as exc:
            failed += 1
            bridge.execute(
                "update recommendation_seen set last_error = ? where id = ?",
                (str(exc)[:500], row["id"]),
            )
    bridge.execute(
        "update runs set finished_at = ?, skipped = ?, failed = ?, deleted = ? where id = ?",
        (now().isoformat(), skipped, failed, deleted, run_id),
    )
    bridge.commit()
    log(f"complete deleted={deleted} skipped={skipped} failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
