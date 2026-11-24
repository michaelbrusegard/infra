#!/usr/bin/env python3
import json
import os
import random
import re
import sqlite3
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime, timedelta
from pathlib import Path

API_URL = os.environ.get("LISTENBRAINZ_API_URL", "https://api.listenbrainz.org").rstrip(
    "/"
)
USERNAME = os.environ.get("LISTENBRAINZ_USERNAME", "").strip()
TOKEN = os.environ.get("LISTENBRAINZ_TOKEN", "").strip()
MUSICGRABBER_URL = os.environ.get("MUSICGRABBER_URL", "").rstrip("/")
MUSIC_ROOT = Path(os.environ.get("MUSIC_ROOT", "/music"))
STATE_DB = Path(os.environ.get("STATE_DB", "/state/listenbrainz-bridge.db"))
NAVIDROME_DB = Path(os.environ.get("NAVIDROME_DB", "/navidrome/navidrome.db"))
METRICS_PATH = Path(os.environ.get("METRICS_PATH", "/state/metrics/listenbrainz.txt"))
MAX_TRACKS_PER_RUN = int(os.environ.get("MAX_TRACKS_PER_RUN", "25"))
PRIORITY_SOURCE = os.environ.get("PRIORITY_SOURCE", "monochrome")
PREFERRED_SOURCES = os.environ.get("PREFERRED_SOURCES", "all")
CONVERT_TO_FLAC = os.environ.get("CONVERT_TO_FLAC", "true").lower() == "true"
AUDIO_SUFFIXES = {".aac", ".flac", ".m4a", ".mp3", ".ogg", ".opus", ".wav"}
LOSSY_SUFFIXES = {".aac", ".m4a", ".mp3", ".ogg", ".opus"}
QUEUE_RETRY_AFTER_SECONDS = 24 * 60 * 60
STALE_JOB_MARGIN = timedelta(hours=1)
WEEKLY_TRACKS = 50
MAX_TRACKS_PER_ARTIST = 2
RECENT_LISTEN_DAYS = 60

PLAYLISTS = {
    "daily_jams": {
        "title": "ListenBrainz Daily Jams",
        "matches": ("daily jams",),
        "path": MUSIC_ROOT / "Playlists" / "ListenBrainz Daily Jams.m3u",
    },
    "weekly_jams": {
        "title": "ListenBrainz Weekly Jams",
        "path": MUSIC_ROOT / "Playlists" / "ListenBrainz Weekly Jams.m3u",
    },
    "weekly_exploration": {
        "title": "ListenBrainz Weekly Exploration",
        "path": MUSIC_ROOT / "Playlists" / "ListenBrainz Weekly Exploration.m3u",
    },
}


def now():
    return datetime.now(UTC).replace(microsecond=0).isoformat()


def parse_time(value):
    try:
        parsed = datetime.fromisoformat((value or "").replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def log(message):
    print(message, flush=True)


def normalize(value):
    value = value or ""
    value = value.lower()
    value = re.sub(
        r"\[[^\]]+\]|\([^\)]*(remaster|remix|live|edit|version)[^\)]*\)", " ", value
    )
    value = re.sub(r"^[0-9]+[ ._-]+", "", value)
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def track_key(artist, title):
    return f"{normalize(artist)}::{normalize(title)}"


def db():
    STATE_DB.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(STATE_DB)
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        create table if not exists recommendation_seen(
          id text primary key,
          playlist_type text not null,
          recording_mbid text,
          artist text not null,
          title text not null,
          status text not null,
          import_id text,
          local_path text,
          first_seen text not null,
          last_seen text not null,
          queued_at text,
          downloaded_at text,
          last_error text
        );
        create table if not exists runs(
          id integer primary key autoincrement,
          kind text not null,
          started_at text not null,
          finished_at text,
          fetched integer default 0,
          queued integer default 0,
          skipped integer default 0,
          failed integer default 0,
          deleted integer default 0
        );
        create table if not exists playlist_snapshot(
          playlist_type text primary key,
          playlist_mbid text not null,
          source_title text not null,
          source_date text,
          fetched_at text not null
        );
        create table if not exists playlist_membership(
          playlist_type text not null,
          recommendation_id text not null,
          position integer not null,
          primary key(playlist_type, recommendation_id)
        );
        create index if not exists playlist_membership_order
          on playlist_membership(playlist_type, position);
        """
    )
    return conn


def http_json(method, url, payload=None, timeout=30):
    headers = {"User-Agent": "asgard-listenbrainz-bridge/1.0"}
    if TOKEN:
        headers["Authorization"] = f"Token {TOKEN}"
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    attempts = 4 if method == "GET" else 1
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                body = response.read()
            return json.loads(body.decode("utf-8")) if body else {}
        except urllib.error.HTTPError as exc:
            if exc.code not in {429, 500, 502, 503, 504} or attempt == attempts:
                raise
            error = exc
        except (urllib.error.URLError, TimeoutError, ssl.SSLError) as exc:
            if attempt == attempts:
                raise
            error = exc
        delay = 2**attempt
        log(f"GET retry attempt={attempt + 1}/{attempts} delay={delay}s error={error}")
        time.sleep(delay)
    raise RuntimeError("HTTP retry loop exhausted")


def musicgrabber_json(method, path, payload=None):
    if not MUSICGRABBER_URL:
        raise RuntimeError("MUSICGRABBER_URL is not configured")
    return http_json(method, f"{MUSICGRABBER_URL}{path}", payload=payload, timeout=60)


def user_api(path):
    if not USERNAME:
        raise RuntimeError("LISTENBRAINZ_USERNAME is not configured")
    return API_URL + path.format(user=urllib.parse.quote(USERNAME))


def recommendation_playlists():
    payload = http_json(
        "GET",
        user_api("/1/user/{user}/playlists/recommendations?count=100"),
    )
    return payload.get("playlists") or payload.get("playlist") or []


def unwrap_playlist(entry):
    return entry.get("playlist", entry) if isinstance(entry, dict) else {}


def playlist_title(entry):
    playlist = unwrap_playlist(entry)
    return str(playlist.get("title") or playlist.get("name") or "")


def playlist_identifier(entry):
    playlist = unwrap_playlist(entry)
    identifier = (
        playlist.get("identifier")
        or playlist.get("id")
        or playlist.get("playlist_mbid")
    )
    if isinstance(identifier, list):
        identifier = identifier[0] if identifier else None
    if not identifier:
        return None
    identifier = str(identifier).rstrip("/")
    return identifier.split("/")[-1]


def playlist_date(entry):
    playlist = unwrap_playlist(entry)
    return str(playlist.get("date") or "")


def find_recommendation_playlists():
    candidates = {key: [] for key in PLAYLISTS}
    for entry in recommendation_playlists():
        title = playlist_title(entry).lower()
        for playlist_type, spec in PLAYLISTS.items():
            if any(match in title for match in spec.get("matches", ())):
                identifier = playlist_identifier(entry)
                if identifier:
                    candidates[playlist_type].append(entry)
    found = {}
    for playlist_type, entries in candidates.items():
        if not entries:
            continue
        entry = max(entries, key=playlist_date)
        identifier = playlist_identifier(entry)
        found[playlist_type] = {
            "identifier": identifier,
            "title": playlist_title(entry),
            "date": playlist_date(entry),
        }
        log(f"matched {playlist_type}: {playlist_title(entry)} ({identifier})")
    return found


def extract_recording_mbid(track):
    identifiers = track.get("identifier") or []
    if isinstance(identifiers, str):
        identifiers = [identifiers]
    for raw_identifier in identifiers:
        identifier = str(raw_identifier)
        if "musicbrainz.org/recording/" in identifier:
            return identifier.rstrip("/").split("/")[-1]
    extension = track.get("extension") or {}
    candidates = [
        extension.get("https://musicbrainz.org/doc/jspf#track", {}).get(
            "additional_metadata", {}
        ),
        extension.get("additional_metadata", {}),
        extension,
    ]
    for candidate in candidates:
        for key in ("recording_mbid", "recording_msid", "musicbrainz_recordingid"):
            value = candidate.get(key) if isinstance(candidate, dict) else None
            if value:
                return str(value)
    return None


def extract_track(track):
    title = track.get("title") or track.get("track_name")
    artist = track.get("creator") or track.get("artist") or track.get("artist_name")
    extension = track.get("extension") or {}
    for candidate in (
        extension.get("https://musicbrainz.org/doc/jspf#track", {}).get(
            "additional_metadata", {}
        ),
        extension.get("additional_metadata", {}),
        extension,
    ):
        if not isinstance(candidate, dict):
            continue
        title = title or candidate.get("track_name") or candidate.get("title")
        artist = artist or candidate.get("artist_name") or candidate.get("artist")
    if not title or not artist:
        return None
    return {
        "artist": str(artist).strip(),
        "title": str(title).strip(),
        "recording_mbid": extract_recording_mbid(track),
    }


def fetch_playlist_tracks(playlist_mbid):
    payload = http_json(
        "GET", f"{API_URL}/1/playlist/{playlist_mbid}?fetch_metadata=true"
    )
    playlist = payload.get("playlist", payload)
    tracks = playlist.get("track") or playlist.get("tracks") or []
    result = []
    for track in tracks:
        extracted = extract_track(track)
        if extracted:
            result.append(extracted)
    return result


def build_weekly_tracks(playlist_type, seed):
    payload = http_json(
        "GET",
        user_api("/1/cf/recommendation/user/{user}/recording?count=1000"),
    )
    recs = (payload.get("payload") or {}).get("mbids") or []
    feedback = http_json(
        "GET",
        user_api("/1/feedback/user/{user}/get-feedback?score=-1&count=1000"),
    )
    hated = {item.get("recording_mbid") for item in feedback.get("feedback") or []}
    cutoff = datetime.now(UTC) - timedelta(days=RECENT_LISTEN_DAYS)
    mbids = []
    for rec in recs:
        mbid = rec.get("recording_mbid")
        listened = rec.get("latest_listened_at")
        if not mbid or mbid in hated:
            continue
        if playlist_type == "weekly_exploration":
            keep = listened is None
        else:
            keep = listened is not None and datetime.fromisoformat(listened) < cutoff
        if keep:
            mbids.append(mbid)

    tracks = []
    per_artist = {}
    for start in range(0, len(mbids), 50):
        if len(tracks) >= WEEKLY_TRACKS:
            break
        chunk = mbids[start : start + 50]
        metadata = http_json(
            "GET",
            f"{API_URL}/1/metadata/recording/?recording_mbids={','.join(chunk)}&inc=artist",
        )
        for mbid in chunk:
            entry = metadata.get(mbid) or {}
            title = (entry.get("recording") or {}).get("name")
            artist = (entry.get("artist") or {}).get("name")
            if (
                not title
                or not artist
                or per_artist.get(artist, 0) >= MAX_TRACKS_PER_ARTIST
            ):
                continue
            per_artist[artist] = per_artist.get(artist, 0) + 1
            tracks.append({"artist": artist, "title": title, "recording_mbid": mbid})
            if len(tracks) >= WEEKLY_TRACKS:
                break
    random.Random(seed).shuffle(tracks)
    return tracks


def weekly_playlist(conn, playlist_type):
    """Return this week's playlist, built from the recommendations once a week.

    ListenBrainz's own weekly job stalls for weeks at a time, so the bridge
    builds weekly playlists itself, then reuses the stored track list so the
    playlist stays put while the recommendations change daily.
    """
    today = datetime.now(UTC).date()
    monday = (today - timedelta(days=today.weekday())).isoformat()
    source = {
        "identifier": f"local:{playlist_type}:{monday}",
        "title": f"{PLAYLISTS[playlist_type]['title']}, week of {monday}",
        "date": monday,
    }
    rows = conn.execute(
        """
        select r.artist, r.title, r.recording_mbid
          from playlist_snapshot s
          join playlist_membership m on m.playlist_type = s.playlist_type
          join recommendation_seen r on r.id = m.recommendation_id
         where s.playlist_type = ? and s.playlist_mbid = ?
         order by m.position
        """,
        (playlist_type, source["identifier"]),
    ).fetchall()
    if rows:
        log(f"reusing {playlist_type}: {source['title']}")
        return source, [dict(row) for row in rows]
    log(f"building {playlist_type}: {source['title']}")
    return source, build_weekly_tracks(playlist_type, source["identifier"])


def clean_title_from_file(path):
    stem = path.stem
    stem = re.sub(r"^[0-9]+[ ._-]+", "", stem)
    return stem.strip()


def navidrome_tracks():
    """Index Navidrome's tracks by their tags.

    Tags name the credited artists, so they match recommendations that the
    folder layout misses: duets filed under one artist, and compilations
    filed under Compilations.
    """
    if not NAVIDROME_DB.exists():
        return []
    try:
        conn = sqlite3.connect(f"file:{NAVIDROME_DB}?mode=ro", uri=True)
        try:
            return conn.execute(
                "select path, artist, title from media_file where missing = 0"
            ).fetchall()
        finally:
            conn.close()
    except sqlite3.Error as exc:
        log(f"navidrome library lookup failed: {exc}")
        return []


def local_index():
    index = {}
    for rel, artist, title in navidrome_tracks():
        path = MUSIC_ROOT / rel
        if path.suffix.lower() in AUDIO_SUFFIXES:
            index.setdefault(track_key(artist, title), path)
    for root_name in ("Albums", "Singles"):
        root = MUSIC_ROOT / root_name
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in AUDIO_SUFFIXES:
                continue
            try:
                rel = path.relative_to(root)
            except ValueError:
                continue
            parts = rel.parts
            if (root_name == "Albums" and len(parts) >= 3) or (
                root_name == "Singles" and len(parts) >= 2
            ):
                artist = parts[0]
                title = clean_title_from_file(path)
            else:
                continue
            index.setdefault(track_key(artist, title), path)
    return index


def upsert_seen(conn, playlist_type, rec, status, local_path=None):
    timestamp = now()
    rec_id = (
        rec["recording_mbid"]
        or f"{playlist_type}:{track_key(rec['artist'], rec['title'])}"
    )
    existing = conn.execute(
        "select * from recommendation_seen where id = ?",
        (rec_id,),
    ).fetchone()
    if existing:
        conn.execute(
            """
            update recommendation_seen
               set last_seen = ?,
                   local_path = coalesce(?, local_path),
                   -- A different file than the one the bridge downloaded
                   -- was already in the library, so cleanup must not
                   -- treat it as the bridge's download.
                   downloaded_at = case
                     when ? is not null and ? is not local_path then null
                     else downloaded_at
                   end,
                   status = case
                     when ? in ('downloaded', 'lossy_fallback') then ?
                     when status in ('queued', 'downloaded', 'lossy_fallback') then status
                     else ?
                   end
             where id = ?
            """,
            (
                timestamp,
                str(local_path) if local_path else None,
                str(local_path) if local_path else None,
                str(local_path) if local_path else None,
                status,
                status,
                status,
                rec_id,
            ),
        )
    else:
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, recording_mbid, artist, title, status,
              local_path, first_seen, last_seen
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                rec_id,
                playlist_type,
                rec["recording_mbid"],
                rec["artist"],
                rec["title"],
                status,
                str(local_path) if local_path else None,
                timestamp,
                timestamp,
            ),
        )
    return rec_id


def replace_playlist_snapshot(conn, playlist_type, source, recommendation_ids):
    conn.execute(
        """
        insert into playlist_snapshot(
          playlist_type, playlist_mbid, source_title, source_date, fetched_at
        ) values (?, ?, ?, ?, ?)
        on conflict(playlist_type) do update set
          playlist_mbid = excluded.playlist_mbid,
          source_title = excluded.source_title,
          source_date = excluded.source_date,
          fetched_at = excluded.fetched_at
        """,
        (
            playlist_type,
            source["identifier"],
            source["title"],
            source["date"],
            now(),
        ),
    )
    conn.execute(
        "delete from playlist_membership where playlist_type = ?",
        (playlist_type,),
    )
    for position, rec_id in enumerate(recommendation_ids):
        conn.execute(
            """
            insert into playlist_membership(
              playlist_type, recommendation_id, position
            ) values (?, ?, ?)
            on conflict(playlist_type, recommendation_id) do update set
              position = min(position, excluded.position)
            """,
            (playlist_type, rec_id, position),
        )


def has_playlist_snapshot(conn, playlist_type):
    return (
        conn.execute(
            "select 1 from playlist_snapshot where playlist_type = ?",
            (playlist_type,),
        ).fetchone()
        is not None
    )


def mark_queued(conn, ids, import_id):
    timestamp = now()
    for rec_id in ids:
        conn.execute(
            """
            update recommendation_seen
               set status = 'queued', import_id = ?, queued_at = ?, last_error = null
             where id = ?
            """,
            (import_id, timestamp, rec_id),
        )


def mark_failed(conn, ids, error):
    for rec_id in ids:
        conn.execute(
            "update recommendation_seen set status = 'failed', last_error = ? where id = ?",
            (error[:500], rec_id),
        )


def find_local(index, artist, title):
    return index.get(track_key(artist, title))


def recommendation_needs_download(conn, row):
    status = row["status"]
    if status in {"downloaded", "lossy_fallback"}:
        local_path = Path(row["local_path"]) if row["local_path"] else None
        if local_path and local_path.exists():
            return False
        conn.execute(
            """
            update recommendation_seen
               set status = 'seen', local_path = null,
                   last_error = 'downloaded file is missing'
             where id = ?
            """,
            (row["id"],),
        )
        return True
    if status == "queued":
        queued_at = parse_time(row["queued_at"])
        age = datetime.now(UTC) - queued_at if queued_at is not None else None
        if age is not None and age.total_seconds() < QUEUE_RETRY_AFTER_SECONDS:
            return False
        conn.execute(
            """
            update recommendation_seen
               set status = 'seen', import_id = null, queued_at = null,
                   last_error = 'queued job expired before completion'
             where id = ?
            """,
            (row["id"],),
        )
        return True
    return True


def playlist_line(path):
    playlist_dir = MUSIC_ROOT / "Playlists"
    try:
        return os.path.relpath(path, playlist_dir)
    except ValueError:
        return str(path)


def write_playlist(path, title, paths):
    path.parent.mkdir(parents=True, exist_ok=True)
    unique = []
    seen = set()
    for item in paths:
        line = playlist_line(item)
        if line not in seen:
            seen.add(line)
            unique.append(line)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("#EXTM3U\n")
        handle.write(f"#PLAYLIST:{title}\n")
        for line in unique:
            handle.write(f"{line}\n")
    log(f"wrote playlist {path} tracks={len(unique)}")


def completed_job_path(job):
    final_path = job.get("final_path")
    if final_path:
        path = Path(final_path)
        if path.exists():
            return path
    match = re.match(r"^Already exists: (.+)$", job.get("error") or "")
    if not match:
        return None
    relative = Path(match.group(1))
    candidates = []
    for root_name in ("Albums", "Singles"):
        root = MUSIC_ROOT / root_name
        if not root.exists():
            continue
        for path in root.rglob(relative.name):
            try:
                path.relative_to(root)
            except ValueError:
                continue
            if path.is_file() and path.parts[-len(relative.parts) :] == relative.parts:
                candidates.append(path)
    return candidates[0] if len(candidates) == 1 else None


def refresh_musicgrabber_status(conn):
    local = local_index()
    try:
        jobs = musicgrabber_json("GET", "/api/jobs?limit=10000").get("jobs", [])
    except Exception as exc:
        log(f"musicgrabber status refresh failed: {exc}")
        return
    tracked = conn.execute(
        """
        select id, artist, title, status, queued_at
          from recommendation_seen
         where status in ('queued', 'downloaded', 'lossy_fallback')
        """
    ).fetchall()
    by_key = {track_key(row["artist"], row["title"]): row for row in tracked}
    by_title = {}
    ambiguous_titles = set()
    for row in tracked:
        title = normalize(row["title"])
        if title in by_title:
            ambiguous_titles.add(title)
        else:
            by_title[title] = row
    for title in ambiguous_titles:
        by_title.pop(title, None)
    jobs.sort(
        key=lambda job: job.get("completed_at") or job.get("created_at") or "",
        reverse=True,
    )
    timestamp = now()
    handled = set()
    for job in jobs:
        key = track_key(job.get("artist"), job.get("title"))
        row = by_key.get(key) or by_title.get(normalize(job.get("title")))
        if not row or row["id"] in handled:
            continue
        created_at = parse_time(job.get("created_at"))
        queued_at = parse_time(row["queued_at"])
        if created_at and queued_at and created_at < queued_at - STALE_JOB_MARGIN:
            continue
        handled.add(row["id"])
        status = job.get("status")
        if status == "completed":
            local_path = completed_job_path(job) or find_local(
                local,
                row["artist"],
                row["title"],
            )
            if not local_path:
                log(
                    "musicgrabber completed without a resolvable local file: "
                    f"{row['artist']} - {row['title']}"
                )
                continue
            quality = job.get("audio_quality") or ""
            next_status = (
                "lossy_fallback"
                if local_path.suffix.lower() in LOSSY_SUFFIXES
                else "downloaded"
            )
            already_existed = (job.get("error") or "").startswith("Already exists")
            conn.execute(
                """
                update recommendation_seen
                   set status = ?,
                       downloaded_at = case
                         when ? then null
                         else coalesce(downloaded_at, ?)
                       end,
                       local_path = ?, last_error = ?
                 where id = ?
                """,
                (
                    next_status,
                    already_existed,
                    timestamp,
                    str(local_path),
                    quality,
                    row["id"],
                ),
            )
        elif status == "failed" and row["status"] == "queued":
            conn.execute(
                "update recommendation_seen set status = 'failed', last_error = ? where id = ?",
                ((job.get("error") or "musicgrabber job failed")[:500], row["id"]),
            )


def queue_missing(conn, queue):
    if not queue:
        return 0
    songs = "\n".join(f"{rec['artist']} - {rec['title']}" for _, rec in queue)
    payload = {
        "songs": songs,
        "create_playlist": False,
        "convert_to_flac": CONVERT_TO_FLAC,
        "use_playlists_dir": False,
        "preferred_sources": PREFERRED_SOURCES,
        "priority_source": PRIORITY_SOURCE,
    }
    ids = [rec_id for rec_id, _ in queue]
    try:
        response = musicgrabber_json("POST", "/api/bulk-import-async", payload)
        import_id = response.get("import_id") or ""
        mark_queued(conn, ids, import_id)
        log(f"queued tracks={len(ids)} import_id={import_id}")
        return len(ids)
    except Exception as exc:
        mark_failed(conn, ids, str(exc))
        raise


def fair_queue(candidates, limit):
    selected = []
    selected_ids = set()
    offsets = dict.fromkeys(PLAYLISTS, 0)
    while len(selected) < limit:
        added = False
        for playlist_type in PLAYLISTS:
            entries = candidates[playlist_type]
            while offsets[playlist_type] < len(entries):
                item = entries[offsets[playlist_type]]
                offsets[playlist_type] += 1
                if item[0] in selected_ids:
                    continue
                selected.append((playlist_type, *item))
                selected_ids.add(item[0])
                added = True
                break
            if len(selected) >= limit:
                break
        if not added:
            break
    return selected


def current_playlist_paths(conn, playlist_type, local):
    rows = conn.execute(
        """
        select r.artist, r.title, r.local_path
          from playlist_membership m
          join recommendation_seen r on r.id = m.recommendation_id
         where m.playlist_type = ?
           and r.status in ('downloaded', 'lossy_fallback')
         order by m.position
        """,
        (playlist_type,),
    ).fetchall()
    paths = []
    for row in rows:
        path = (
            Path(row["local_path"])
            if row["local_path"]
            else find_local(local, row["artist"], row["title"])
        )
        if path and path.exists():
            paths.append(path)
    return paths


def refresh_playlist_status_counts(conn, stats):
    for playlist_type in PLAYLISTS:
        counts = conn.execute(
            """
            select r.status, count(*) as count
              from playlist_membership m
              join recommendation_seen r on r.id = m.recommendation_id
             where m.playlist_type = ?
             group by r.status
            """,
            (playlist_type,),
        ).fetchall()
        by_status = {row["status"]: row["count"] for row in counts}
        stats[playlist_type]["downloaded"] = by_status.get(
            "downloaded", 0
        ) + by_status.get("lossy_fallback", 0)
        stats[playlist_type]["failed"] = by_status.get("failed", 0)


def previous_success_timestamp():
    try:
        text = METRICS_PATH.read_text(encoding="utf-8")
    except OSError:
        return 0
    match = re.search(
        r"^listenbrainz_bridge_last_success_timestamp_seconds ([0-9]+)$",
        text,
        flags=re.MULTILINE,
    )
    return int(match.group(1)) if match else 0


def write_metrics(stats, success):
    timestamp = int(time.time())
    last_success = timestamp if success else previous_success_timestamp()
    lines = [
        "# HELP listenbrainz_bridge_last_run_success Whether the latest bridge run succeeded.",
        "# TYPE listenbrainz_bridge_last_run_success gauge",
        f"listenbrainz_bridge_last_run_success {1 if success else 0}",
        "# HELP listenbrainz_bridge_last_run_timestamp_seconds Unix timestamp of the latest bridge run.",
        "# TYPE listenbrainz_bridge_last_run_timestamp_seconds gauge",
        f"listenbrainz_bridge_last_run_timestamp_seconds {timestamp}",
        "# HELP listenbrainz_bridge_last_success_timestamp_seconds Unix timestamp of the latest successful bridge run.",
        "# TYPE listenbrainz_bridge_last_success_timestamp_seconds gauge",
        f"listenbrainz_bridge_last_success_timestamp_seconds {last_success}",
    ]
    metric_help = {
        "source_available": "Whether ListenBrainz returned a current source playlist.",
        "upstream": "Tracks in the current upstream playlist.",
        "local": "Current upstream tracks already found locally.",
        "candidates": "Missing current tracks eligible for download.",
        "queued": "Tracks queued for download by the latest run.",
        "downloaded": "Current playlist tracks downloaded or found locally.",
        "failed": "Current playlist tracks with a failed download.",
        "rendered": "Playable tracks written to the local M3U playlist.",
    }
    for key, help_text in metric_help.items():
        name = f"listenbrainz_bridge_playlist_{key}"
        lines.extend([f"# HELP {name} {help_text}", f"# TYPE {name} gauge"])
        lines.extend(
            f'{name}{{playlist_type="{playlist_type}"}} {stats[playlist_type][key]}'
            for playlist_type in PLAYLISTS
        )
    METRICS_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = METRICS_PATH.with_suffix(".tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temporary.replace(METRICS_PATH)


def main():
    conn = db()
    started = now()
    run_id = conn.execute(
        "insert into runs(kind, started_at) values ('bridge', ?) returning id",
        (started,),
    ).fetchone()[0]
    fetched = queued = skipped = failed = 0
    stats = {
        playlist_type: {
            "source_available": 0,
            "upstream": 0,
            "local": 0,
            "candidates": 0,
            "queued": 0,
            "downloaded": 0,
            "failed": 0,
            "rendered": 0,
        }
        for playlist_type in PLAYLISTS
    }
    candidates = {key: [] for key in PLAYLISTS}
    try:
        refresh_musicgrabber_status(conn)
        local = local_index()
        matched = find_recommendation_playlists()
        for playlist_type, spec in PLAYLISTS.items():
            if "matches" in spec:
                source = matched.get(playlist_type)
                if not source:
                    log(
                        f"no ListenBrainz playlist found for {playlist_type}; "
                        "preserving last snapshot"
                    )
                    continue
                tracks = fetch_playlist_tracks(source["identifier"])
            else:
                source, tracks = weekly_playlist(conn, playlist_type)
            stats[playlist_type]["source_available"] = 1
            stats[playlist_type]["upstream"] = len(tracks)
            if not tracks:
                log(
                    f"empty ListenBrainz playlist for {playlist_type}; "
                    "preserving last snapshot"
                )
                continue
            fetched += len(tracks)
            recommendation_ids = []
            for rec in tracks:
                local_path = find_local(local, rec["artist"], rec["title"])
                if local_path:
                    local_status = (
                        "lossy_fallback"
                        if local_path.suffix.lower() in LOSSY_SUFFIXES
                        else "downloaded"
                    )
                    rec_id = upsert_seen(
                        conn,
                        playlist_type,
                        rec,
                        local_status,
                        local_path,
                    )
                    recommendation_ids.append(rec_id)
                    stats[playlist_type]["local"] += 1
                    skipped += 1
                    continue
                rec_id = upsert_seen(conn, playlist_type, rec, "seen")
                recommendation_ids.append(rec_id)
                row = conn.execute(
                    """
                    select id, status, local_path, queued_at
                      from recommendation_seen
                     where id = ?
                    """,
                    (rec_id,),
                ).fetchone()
                if row and not recommendation_needs_download(conn, row):
                    skipped += 1
                    continue
                candidates[playlist_type].append((rec_id, rec))
                stats[playlist_type]["candidates"] += 1
            replace_playlist_snapshot(
                conn,
                playlist_type,
                source,
                recommendation_ids,
            )

        selected = fair_queue(candidates, MAX_TRACKS_PER_RUN)
        for playlist_type, _, _ in selected:
            stats[playlist_type]["queued"] += 1
        skipped += sum(len(items) for items in candidates.values()) - len(selected)
        queue = [(rec_id, rec) for _, rec_id, rec in selected]
        queued = queue_missing(conn, queue)
        conn.commit()
        refresh_musicgrabber_status(conn)
        conn.commit()

        current_local = local_index()
        for playlist_type, spec in PLAYLISTS.items():
            if not has_playlist_snapshot(conn, playlist_type):
                log(
                    f"no stored snapshot for {playlist_type}; "
                    f"preserving playlist {spec['path']}"
                )
                continue
            paths = current_playlist_paths(conn, playlist_type, current_local)
            write_playlist(spec["path"], spec["title"], paths)
            stats[playlist_type]["rendered"] = len(paths)
        refresh_playlist_status_counts(conn, stats)
        write_metrics(stats, success=True)
    except Exception:
        failed += 1
        conn.execute(
            "update runs set finished_at = ?, fetched = ?, queued = ?, skipped = ?, failed = ? where id = ?",
            (now(), fetched, queued, skipped, failed, run_id),
        )
        conn.commit()
        try:
            refresh_playlist_status_counts(conn, stats)
            write_metrics(stats, success=False)
        except Exception as metrics_exc:
            log(f"failed to write failure metrics: {metrics_exc}")
        raise
    conn.execute(
        "update runs set finished_at = ?, fetched = ?, queued = ?, skipped = ?, failed = ? where id = ?",
        (now(), fetched, queued, skipped, failed, run_id),
    )
    conn.commit()
    log("playlist_stats=" + json.dumps(stats, sort_keys=True))
    log(f"complete fetched={fetched} queued={queued} skipped={skipped} failed={failed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
