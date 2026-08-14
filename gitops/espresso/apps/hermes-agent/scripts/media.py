#!/usr/bin/env python3
"""Context-efficient CLI for the allowlisted private media API."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


MISSING = object()
STATUSES = (
    "all",
    "approved",
    "available",
    "pending",
    "processing",
    "unavailable",
    "failed",
    "deleted",
    "completed",
)


def compact(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def safe_text(value: Any) -> str:
    message = str(value)
    token = os.environ.get("MEDIA_API_TOKEN", "")
    if token:
        message = message.replace(token, "[REDACTED]")
    return message[:500]


def require_confirmation(args: argparse.Namespace, action: str) -> None:
    if not getattr(args, "yes", False):
        raise ValueError(f"{action} requires --yes after explicit user confirmation")


def seasons(value: str) -> str | list[int]:
    if value == "all":
        return value
    try:
        parsed = sorted(
            {int(item.strip()) for item in value.split(",") if item.strip()}
        )
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "seasons must be all or comma-separated numbers"
        ) from exc
    if not parsed or any(item < 0 for item in parsed):
        raise argparse.ArgumentTypeError(
            "seasons must be all or non-negative comma-separated numbers"
        )
    return parsed


class MediaClient:
    def __init__(self) -> None:
        self.base_url = os.environ.get(
            "MEDIA_API_URL",
            "http://hermes-media-api.media.svc.cluster.local:8080",
        ).rstrip("/")
        self.token = os.environ.get("MEDIA_API_TOKEN", "").strip()
        if not self.token:
            raise RuntimeError("MEDIA_API_TOKEN is not configured")

    def request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: Any = MISSING,
        timeout: int = 60,
    ) -> Any:
        url = f"{self.base_url}{path}"
        if query:
            values = {key: value for key, value in query.items() if value is not None}
            if values:
                url += "?" + urlencode(values, doseq=True)
        data = None if body is MISSING else json.dumps(body).encode()
        request = Request(
            url,
            data=data,
            method=method,
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {self.token}",
                **({"Content-Type": "application/json"} if data is not None else {}),
            },
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                payload = response.read()
        except HTTPError as exc:
            payload = exc.read(4096)
            detail = self._decode(payload)
            raise RuntimeError(
                f"media API returned HTTP {exc.code}: {safe_text(detail)}"
            ) from exc
        except (URLError, TimeoutError) as exc:
            raise RuntimeError(f"unable to reach media API: {safe_text(exc)}") from exc
        return self._decode(payload)

    @staticmethod
    def _decode(payload: bytes) -> Any:
        if not payload:
            return {"ok": True}
        decoded = payload.decode("utf-8", errors="replace")
        try:
            return json.loads(decoded)
        except json.JSONDecodeError:
            return {"text": decoded[:4096]}

    def get(
        self,
        path: str,
        query: dict[str, Any] | None = None,
        *,
        timeout: int = 60,
    ) -> Any:
        return self.request("GET", path, query=query, timeout=timeout)

    def post(self, path: str, body: dict[str, Any], *, timeout: int = 60) -> Any:
        return self.request("POST", path, body=body, timeout=timeout)


def request_for(args: argparse.Namespace, client: MediaClient) -> Any:
    command = args.command
    if command == "status":
        return client.get("/v1/status")
    if command == "search":
        return client.get(
            "/v1/search",
            {"q": args.query, "type": args.type, "limit": args.limit},
        )
    if command == "request":
        return client.post("/v1/request", {"ref": args.ref, "seasons": args.seasons})
    if command == "requests":
        return client.get("/v1/requests", {"status": args.status, "limit": args.limit})
    if command == "request-show":
        return client.get(f"/v1/request/{args.id}")
    if command == "music-search":
        return client.post(
            "/v1/music-search",
            {"query": args.query, "source": args.source, "limit": args.limit},
            timeout=120,
        )
    if command == "music-sources":
        return client.get("/v1/music-sources")
    if command == "music-download":
        return client.post("/v1/music-download", {"ref": args.ref}, timeout=120)
    if command == "artist-search":
        return client.get("/v1/artist-search", {"q": args.query})
    if command == "albums":
        return client.get("/v1/albums", {"ref": args.ref})
    if command == "album-download":
        return client.post("/v1/album-download", {"ref": args.ref}, timeout=120)
    if command == "music-jobs":
        return client.get(
            "/v1/music-jobs", {"status": args.status, "limit": args.limit}
        )
    if command == "music-job":
        return client.get(f"/v1/music-job/{quote(args.id, safe='')}")
    if command == "album-jobs":
        return client.get("/v1/album-jobs", {"limit": args.limit})
    if command == "album-job":
        return client.get(f"/v1/album-job/{quote(args.id, safe='')}")
    if command in {"queue", "history", "missing"}:
        query = {"app": args.app, "limit": args.limit}
        if command == "history":
            query["query"] = args.query
        return client.get(f"/v1/{command}", query)
    if command == "lookup":
        return client.get(
            "/v1/lookup",
            {"q": args.query, "app": args.app, "limit": args.limit},
        )
    if command == "item":
        return client.get("/v1/item", {"ref": args.ref})
    if command == "episodes":
        return client.get("/v1/episodes", {"ref": args.ref, "season": args.season})
    if command in {"profiles", "formats"}:
        return client.get(f"/v1/{command}", {"app": args.app})
    if command == "releases":
        return client.get("/v1/releases", {"ref": args.ref}, timeout=180)
    if command == "diagnose":
        return client.get("/v1/diagnose", {"ref": args.ref})
    if command == "search-item":
        require_confirmation(args, "search-item")
        return client.post("/v1/search-item", {"ref": args.ref})
    if command == "grab":
        require_confirmation(args, "grab")
        return client.post("/v1/grab", {"ref": args.ref}, timeout=120)
    raise ValueError(f"unsupported command: {command}")


def add_limit(parser: argparse.ArgumentParser, default: int = 20) -> None:
    parser.add_argument(
        "--limit", type=int, choices=range(1, 51), default=default, metavar="1..50"
    )


def add_app(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--app", choices=("sonarr", "radarr"), default="sonarr")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="media",
        description="Request and diagnose private media through an allowlisted CLI.",
    )
    sub = root.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="check media API and upstream service health")

    search = sub.add_parser("search", help="search Seerr for movies or TV series")
    search.add_argument("query")
    search.add_argument("--type", choices=("all", "movie", "tv"), default="all")
    add_limit(search, 10)

    request = sub.add_parser("request", help="request a movie or TV search result")
    request.add_argument("ref")
    request.add_argument(
        "--seasons", type=seasons, default="all", help="all or comma-separated numbers"
    )
    requests = sub.add_parser("requests", help="list recent Seerr requests")
    requests.add_argument("--status", choices=STATUSES, default="all")
    add_limit(requests)
    request_show = sub.add_parser("request-show", help="show one Seerr request")
    request_show.add_argument("id", type=int)

    music_search = sub.add_parser("music-search", help="search for a song")
    music_search.add_argument("query")
    music_search.add_argument(
        "--source",
        default="all",
        help="source id from music-sources (default: all)",
    )
    add_limit(music_search, 10)
    sub.add_parser("music-sources", help="list configured music search sources")
    music_download = sub.add_parser(
        "music-download", help="queue one returned music result"
    )
    music_download.add_argument("ref")
    artist_search = sub.add_parser(
        "artist-search", help="search MusicBrainz for an artist"
    )
    artist_search.add_argument("query")
    albums = sub.add_parser("albums", help="list albums for a returned artist")
    albums.add_argument("ref")
    album_download = sub.add_parser(
        "album-download", help="queue one returned full album"
    )
    album_download.add_argument("ref")
    jobs = sub.add_parser("music-jobs", help="list recent music jobs")
    jobs.add_argument("--status")
    add_limit(jobs)
    job = sub.add_parser("music-job", help="show one music job")
    job.add_argument("id")
    album_jobs = sub.add_parser("album-jobs", help="list recent album imports")
    add_limit(album_jobs, 10)
    album_job = sub.add_parser("album-job", help="show one album import")
    album_job.add_argument("id")

    queue = sub.add_parser("queue", help="show the Sonarr or Radarr queue")
    add_app(queue)
    add_limit(queue)
    history = sub.add_parser("history", help="show recent Sonarr or Radarr history")
    add_app(history)
    history.add_argument("--query")
    add_limit(history)
    missing = sub.add_parser("missing", help="show monitored missing media")
    add_app(missing)
    add_limit(missing)
    lookup = sub.add_parser("lookup", help="find an existing series or movie")
    lookup.add_argument("query")
    add_app(lookup)
    add_limit(lookup, 10)
    item = sub.add_parser("item", help="show one returned series, episode, or movie")
    item.add_argument("ref")
    episodes = sub.add_parser("episodes", help="list episodes for a returned series")
    episodes.add_argument("ref")
    episodes.add_argument("--season", type=int)
    profiles = sub.add_parser("profiles", help="list quality profiles without secrets")
    add_app(profiles)
    formats = sub.add_parser(
        "formats", help="list custom formats without specifications"
    )
    add_app(formats)
    releases = sub.add_parser(
        "releases", help="search releases for a returned media item"
    )
    releases.add_argument("ref")
    diagnose = sub.add_parser(
        "diagnose", help="summarize item, profile, and recent history"
    )
    diagnose.add_argument("ref")
    search_item = sub.add_parser(
        "search-item", help="trigger an automatic search for one returned item"
    )
    search_item.add_argument("ref")
    search_item.add_argument("--yes", action="store_true")
    grab = sub.add_parser("grab", help="grab one non-rejected returned release")
    grab.add_argument("ref")
    grab.add_argument("--yes", action="store_true")
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        compact(request_for(args, MediaClient()))
        return 0
    except (ValueError, RuntimeError) as exc:
        print(f"media: {safe_text(exc)}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(
            f"media: request failed: {type(exc).__name__}: {safe_text(exc)}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
