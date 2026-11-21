import os
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


CONFIGMAP = Path(__file__).parents[1] / "listenbrainz-bridge-configmap.yaml"


def bridge_source():
    text = CONFIGMAP.read_text(encoding="utf-8")
    start = text.index("  bridge.py: |\n") + len("  bridge.py: |\n")
    end = text.index("  cleanup.py: |\n", start)
    return "".join(
        line[4:] if line.startswith("    ") else line
        for line in text[start:end].splitlines(keepends=True)
    )


def load_bridge(root):
    environment = {
        "MUSIC_ROOT": str(root / "music"),
        "STATE_DB": str(root / "state.db"),
        "METRICS_PATH": str(root / "listenbrainz.txt"),
    }
    namespace = {"__name__": "listenbrainz_bridge"}
    with mock.patch.dict(os.environ, environment, clear=False):
        exec(compile(bridge_source(), str(CONFIGMAP), "exec"), namespace)
    return namespace


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
        with mock.patch.object(self.bridge["urllib"].request, "urlopen", urlopen), mock.patch.object(
            self.bridge["time"], "sleep"
        ) as sleep:
            result = self.bridge["http_json"]("GET", "https://example.test/data")

        self.assertEqual({"ok": True}, result)
        self.assertEqual(2, urlopen.call_count)
        sleep.assert_called_once_with(2)

    def test_local_index_includes_opus_files(self):
        path = self.root / "music" / "Singles" / "Kaleo" / "Way Down We Go.opus"
        path.parent.mkdir(parents=True)
        path.touch()

        index = self.bridge["local_index"]()

        self.assertEqual(path, self.bridge["find_local"](index, "Kaleo", "Way Down We Go"))

    def test_upsert_records_local_opus_as_lossy_fallback(self):
        path = self.root / "music" / "Singles" / "Kaleo" / "Way Down We Go.opus"
        path.parent.mkdir(parents=True)
        path.touch()
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)
        rec = {"artist": "Kaleo", "title": "Way Down We Go", "recording_mbid": "recording"}

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
        recs = [{"recording_mbid": f"r{index}", "latest_listened_at": None} for index in range(4)]
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
        recs = [{"recording_mbid": f"r{index}", "latest_listened_at": None} for index in range(5)]
        calls = self.fake_listenbrainz(recs)
        conn = self.bridge["db"]()
        self.addCleanup(conn.close)

        source, first = self.bridge["weekly_playlist"](conn, "weekly_exploration")
        ids = [self.bridge["upsert_seen"](conn, "weekly_exploration", rec, "seen") for rec in first]
        self.bridge["replace_playlist_snapshot"](conn, "weekly_exploration", source, ids)
        calls.clear()
        recs[:] = [{"recording_mbid": "new", "latest_listened_at": None}]

        again_source, again = self.bridge["weekly_playlist"](conn, "weekly_exploration")

        self.assertEqual(source, again_source)
        self.assertEqual(first, again)
        self.assertEqual([], calls)


if __name__ == "__main__":
    unittest.main()
