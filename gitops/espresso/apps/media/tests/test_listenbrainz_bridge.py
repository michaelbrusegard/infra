import os
import sqlite3
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).parents[1] / "scripts"
BRIDGE = SCRIPTS / "listenbrainz-bridge.py"
CLEANUP = SCRIPTS / "listenbrainz-cleanup.py"


def run_script(path, name):
    namespace = {"__name__": name}
    exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"), namespace)
    return namespace


def load_bridge(root):
    environment = {
        "MUSIC_ROOT": str(root / "music"),
        "STATE_DB": str(root / "state.db"),
        "METRICS_PATH": str(root / "listenbrainz.txt"),
        "NAVIDROME_DB": str(root / "navidrome.db"),
    }
    with mock.patch.dict(os.environ, environment, clear=False):
        return run_script(BRIDGE, "listenbrainz_bridge")


def load_cleanup(root):
    with mock.patch.dict(os.environ, {"MUSIC_ROOT": str(root / "music")}, clear=False):
        return run_script(CLEANUP, "listenbrainz_cleanup")


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def read(self):
        return self.body


class ListenBrainzBridgeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bridge = load_bridge(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def test_get_retries_transient_tls_failure(self):
        urlopen = mock.Mock(
            side_effect=[
                urllib.error.URLError("transient TLS EOF"),
                FakeResponse(b'{"ok": true}'),
            ]
        )
        with (
            mock.patch.object(self.bridge["urllib"].request, "urlopen", urlopen),
            mock.patch.object(self.bridge["time"], "sleep") as sleep,
        ):
            result = self.bridge["http_json"]("GET", "https://example.test/data")

        self.assertEqual({"ok": True}, result)
        self.assertEqual(2, urlopen.call_count)
        sleep.assert_called_once_with(2)

    def test_local_index_includes_opus_files(self):
        path = self.root / "music" / "Singles" / "Kaleo" / "Way Down We Go.opus"
        path.parent.mkdir(parents=True)
        path.touch()

        index = self.bridge["local_index"]()

        self.assertEqual(
            path, self.bridge["find_local"](index, "Kaleo", "Way Down We Go")
        )

    def test_upsert_records_local_opus_as_lossy_fallback(self):
        path = self.root / "music" / "Singles" / "Kaleo" / "Way Down We Go.opus"
        path.parent.mkdir(parents=True)
        path.touch()
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        rec = {
            "artist": "Kaleo",
            "title": "Way Down We Go",
            "recording_mbid": "recording",
        }

        self.bridge["upsert_seen"](
            conn,
            "weekly_exploration",
            rec,
            "lossy_fallback",
            path,
        )
        row = conn.execute(
            "select status, local_path from recommendation_seen where id = 'recording'"
        ).fetchone()

        self.assertEqual("lossy_fallback", row["status"])
        self.assertEqual(str(path), row["local_path"])

    def test_completed_job_matches_unique_title_and_records_final_path(self):
        path = (
            self.root
            / "music"
            / "Singles"
            / "The Weeknd with JENNIE & Lily-Rose Depp"
            / "One of the Girls.opus"
        )
        path.parent.mkdir(parents=True)
        path.touch()
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, artist, title, status, first_seen, last_seen, queued_at
            ) values ('recording', 'weekly_exploration', ?, ?, 'queued', ?, ?, ?)
            """,
            (
                "The Weeknd with JENNIE & Lily-Rose Depp",
                "One of the Girls",
                "2026-08-24T00:00:00+00:00",
                "2026-08-24T00:00:00+00:00",
                "2026-08-24T00:00:00+00:00",
            ),
        )
        self.bridge["musicgrabber_json"] = lambda *_args, **_kwargs: {
            "jobs": [
                {
                    "artist": "The Weeknd & JENNIE & Lily-Rose Depp",
                    "title": "One of the Girls",
                    "status": "completed",
                    "completed_at": "2026-08-24T00:05:00Z",
                    "audio_quality": "OPUS 256kbps (from FLAC)",
                    "final_path": str(path),
                }
            ]
        }

        self.bridge["refresh_musicgrabber_status"](conn)
        row = conn.execute(
            "select status, local_path from recommendation_seen where id = 'recording'"
        ).fetchone()

        self.assertEqual("lossy_fallback", row["status"])
        self.assertEqual(str(path), row["local_path"])

    def test_job_from_earlier_request_is_ignored(self):
        remix = (
            self.root
            / "music"
            / "Albums"
            / "Tame Impala"
            / "Dracula (remix)"
            / "Dracula (JENNIE remix).flac"
        )
        remix.parent.mkdir(parents=True)
        remix.touch()
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, artist, title, status, first_seen, last_seen, queued_at
            ) values ('recording', 'weekly_exploration', 'Tame Impala', 'Dracula', 'queued', ?, ?, ?)
            """,
            (
                "2026-09-29T02:35:00+00:00",
                "2026-11-21T00:17:25+00:00",
                "2026-11-21T00:17:25+00:00",
            ),
        )
        self.bridge["musicgrabber_json"] = lambda *_args, **_kwargs: {
            "jobs": [
                {
                    "artist": "Tame Impala",
                    "title": "Dracula",
                    "status": "completed",
                    "created_at": "2026-09-29T02:35:32Z",
                    "completed_at": "2026-09-29T02:35:36Z",
                    "final_path": str(remix),
                },
            ]
        }

        self.bridge["refresh_musicgrabber_status"](conn)
        row = conn.execute(
            "select status, local_path from recommendation_seen where id = 'recording'"
        ).fetchone()

        self.assertEqual("queued", row["status"])
        self.assertIsNone(row["local_path"])

    def test_file_that_already_existed_is_never_cleanup_eligible(self):
        path = (
            self.root
            / "music"
            / "Albums"
            / "Compilations"
            / "Greatest Hits"
            / "07 Don't Stop Me Now.flac"
        )
        path.parent.mkdir(parents=True)
        path.touch()
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, artist, title, status, local_path,
              first_seen, last_seen, queued_at, downloaded_at
            ) values ('recording', 'daily_jams', 'Queen', 'Don\u2019t Stop Me Now', 'downloaded', ?, ?, ?, ?, ?)
            """,
            (
                str(path),
                "2026-08-19T14:35:03+00:00",
                "2026-08-19T14:35:03+00:00",
                "2026-08-19T14:35:03+00:00",
                "2026-08-19T14:40:00+00:00",
            ),
        )
        self.bridge["musicgrabber_json"] = lambda *_args, **_kwargs: {
            "jobs": [
                {
                    "artist": "Queen",
                    "title": "Don\u2019t Stop Me Now",
                    "status": "completed",
                    "created_at": "2026-08-19T14:35:30Z",
                    "completed_at": "2026-08-19T14:36:00Z",
                    "error": "Already exists: Greatest Hits/07 Don't Stop Me Now.flac",
                    "final_path": None,
                }
            ]
        }

        self.bridge["refresh_musicgrabber_status"](conn)
        row = conn.execute(
            "select status, local_path, downloaded_at from recommendation_seen where id = 'recording'"
        ).fetchone()

        self.assertEqual("downloaded", row["status"])
        self.assertEqual(str(path), row["local_path"])
        self.assertIsNone(row["downloaded_at"])

    def test_library_copy_found_later_is_never_cleanup_eligible(self):
        downloaded = (
            self.root / "music" / "Singles" / "Lady Gaga" / "Die With a Smile.opus"
        )
        library = (
            self.root
            / "music"
            / "Albums"
            / "Lady Gaga"
            / "Die With A Smile - Single"
            / "01 Die With A Smile.flac"
        )
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, artist, title, status, local_path,
              first_seen, last_seen, queued_at, downloaded_at
            ) values ('recording', 'daily_jams', 'Lady Gaga & Bruno Mars', 'Die With a Smile', 'downloaded', ?, ?, ?, ?, ?)
            """,
            (
                str(downloaded),
                "2026-08-02T14:35:01+00:00",
                "2026-08-02T14:35:01+00:00",
                "2026-08-02T14:35:01+00:00",
                "2026-08-02T14:40:00+00:00",
            ),
        )
        rec = {
            "artist": "Lady Gaga & Bruno Mars",
            "title": "Die With a Smile",
            "recording_mbid": "recording",
        }

        self.bridge["upsert_seen"](conn, "daily_jams", rec, "downloaded", downloaded)
        same = conn.execute("select downloaded_at from recommendation_seen").fetchone()
        self.bridge["upsert_seen"](conn, "daily_jams", rec, "downloaded", library)
        other = conn.execute(
            "select local_path, downloaded_at from recommendation_seen"
        ).fetchone()

        self.assertEqual("2026-08-02T14:40:00+00:00", same["downloaded_at"])
        self.assertEqual(str(library), other["local_path"])
        self.assertIsNone(other["downloaded_at"])

    def test_local_index_matches_tagged_artist_and_title(self):
        path = (
            self.root
            / "music"
            / "Albums"
            / "Compilations"
            / "Greatest Hits"
            / "14 Iris.flac"
        )
        path.parent.mkdir(parents=True)
        path.touch()
        navidrome = sqlite3.connect(self.root / "navidrome.db")
        navidrome.execute(
            "create table media_file(path text, artist text, title text, missing bool)"
        )
        navidrome.execute(
            "insert into media_file values (?, 'Goo Goo Dolls', 'Iris', 0)",
            ("Albums/Compilations/Greatest Hits/14 Iris.flac",),
        )
        navidrome.commit()
        navidrome.close()

        index = self.bridge["local_index"]()

        self.assertEqual(
            path, self.bridge["find_local"](index, "Goo Goo Dolls", "Iris")
        )

    def test_completed_duplicate_resolves_already_exists_path(self):
        path = (
            self.root
            / "music"
            / "Albums"
            / "Compilations"
            / "Greatest Hits"
            / "07 Don't Stop Me Now.flac"
        )
        path.parent.mkdir(parents=True)
        path.touch()

        resolved = self.bridge["completed_job_path"](
            {
                "error": "Already exists: Greatest Hits/07 Don't Stop Me Now.flac",
                "final_path": None,
            }
        )

        self.assertEqual(path, resolved)

    def test_missing_downloaded_file_becomes_download_candidate(self):
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, artist, title, status, local_path, first_seen, last_seen
            ) values ('recording', 'daily_jams', 'Artist', 'Title', 'downloaded', ?, ?, ?)
            """,
            (
                str(self.root / "missing.flac"),
                "2026-08-24T00:00:00+00:00",
                "2026-08-24T00:00:00+00:00",
            ),
        )
        row = conn.execute(
            "select id, status, local_path, queued_at from recommendation_seen where id = 'recording'"
        ).fetchone()

        self.assertTrue(self.bridge["recommendation_needs_download"](conn, row))
        status = conn.execute(
            "select status from recommendation_seen where id = 'recording'"
        ).fetchone()["status"]
        self.assertEqual("seen", status)

    def test_deleted_recommendation_is_downloaded_again(self):
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        conn.execute(
            """
            insert into recommendation_seen(
              id, playlist_type, artist, title, status, first_seen, last_seen
            ) values ('recording', 'daily_jams', 'Artist', 'Title', 'deleted', ?, ?)
            """,
            ("2026-08-24T00:00:00+00:00", "2026-08-24T00:00:00+00:00"),
        )
        rec = {"artist": "Artist", "title": "Title", "recording_mbid": "recording"}

        self.bridge["upsert_seen"](conn, "daily_jams", rec, "seen")
        row = conn.execute(
            "select id, status, local_path, queued_at from recommendation_seen where id = 'recording'"
        ).fetchone()

        self.assertEqual("seen", row["status"])
        self.assertTrue(self.bridge["recommendation_needs_download"](conn, row))

    def test_cleanup_keeps_files_in_listenbrainz_playlists(self):
        cleanup = load_cleanup(self.root)
        path = self.root / "music" / "Singles" / "Kaleo" / "Way Down We Go.opus"
        path.parent.mkdir(parents=True)
        path.touch()
        playlist = (
            self.root / "music" / "Playlists" / "ListenBrainz Weekly Exploration.m3u"
        )
        playlist.parent.mkdir(parents=True)
        playlist.write_text(
            "#EXTM3U\n../Singles/Kaleo/Way Down We Go.opus\n", encoding="utf-8"
        )

        self.assertTrue(cleanup["protected_by_playlist"](path))

    def fake_listenbrainz(self, recs, hated=(), metadata=None):
        calls = []
        metadata = metadata or {
            rec["recording_mbid"]: {
                "recording": {"name": f"Title {rec['recording_mbid']}"},
                "artist": {"name": f"Artist {rec['recording_mbid']}"},
            }
            for rec in recs
        }

        def http_json(method, url, payload=None, timeout=30):
            calls.append(url)
            if "/cf/recommendation/" in url:
                return {"payload": {"mbids": recs}}
            if "/get-feedback" in url:
                return {"feedback": [{"recording_mbid": mbid} for mbid in hated]}
            if "/metadata/recording/" in url:
                return metadata
            raise AssertionError(url)

        self.bridge["USERNAME"] = "user"
        self.bridge["http_json"] = http_json
        return calls

    def test_weekly_playlists_follow_listenbrainz_rules(self):
        recent = self.bridge["now"]()
        recs = [
            {"recording_mbid": "never", "latest_listened_at": None},
            {"recording_mbid": "hated", "latest_listened_at": None},
            {"recording_mbid": "old", "latest_listened_at": "2020-01-01T00:00:00.000Z"},
            {"recording_mbid": "recent", "latest_listened_at": recent},
        ]
        self.fake_listenbrainz(recs, hated=["hated"])

        exploration = self.bridge["build_weekly_tracks"]("weekly_exploration", "seed")
        jams = self.bridge["build_weekly_tracks"]("weekly_jams", "seed")

        self.assertEqual(["never"], [track["recording_mbid"] for track in exploration])
        self.assertEqual(["old"], [track["recording_mbid"] for track in jams])
        self.assertEqual("Artist old", jams[0]["artist"])
        self.assertEqual("Title old", jams[0]["title"])

    def test_weekly_playlist_limits_tracks_per_artist(self):
        recs = [
            {"recording_mbid": f"r{index}", "latest_listened_at": None}
            for index in range(4)
        ]
        metadata = {
            rec["recording_mbid"]: {
                "recording": {"name": rec["recording_mbid"]},
                "artist": {"name": "Same Artist"},
            }
            for rec in recs
        }
        self.fake_listenbrainz(recs, metadata=metadata)

        tracks = self.bridge["build_weekly_tracks"]("weekly_exploration", "seed")

        self.assertEqual({"r0", "r1"}, {track["recording_mbid"] for track in tracks})

    def test_weekly_playlist_is_reused_within_the_week(self):
        recs = [
            {"recording_mbid": f"r{index}", "latest_listened_at": None}
            for index in range(5)
        ]
        calls = self.fake_listenbrainz(recs)
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)

        source, first = self.bridge["weekly_playlist"](conn, "weekly_exploration")
        ids = [
            self.bridge["upsert_seen"](conn, "weekly_exploration", rec, "seen")
            for rec in first
        ]
        self.bridge["replace_playlist_snapshot"](
            conn, "weekly_exploration", source, ids
        )
        calls.clear()
        recs[:] = [{"recording_mbid": "new", "latest_listened_at": None}]

        again_source, again = self.bridge["weekly_playlist"](conn, "weekly_exploration")

        self.assertEqual(source, again_source)
        self.assertEqual(first, again)
        self.assertEqual([], calls)


if __name__ == "__main__":
    unittest.main()
