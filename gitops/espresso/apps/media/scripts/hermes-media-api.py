#!/usr/bin/env python3
"""Allowlisted media-stack API for Hermes Agent."""

from __future__ import annotations

import hmac
import json
import os
import re
import secrets
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlencode, urlparse
from urllib.request import Request, urlopen


MAX_BODY = 64 * 1024
MAX_RESULTS = 50
REF_TTL_SECONDS = 30 * 60

SEERR_URL = os.environ.get(
    "SEERR_URL", "http://seerr-internal.media.svc.cluster.local:5055/api/v1"
).rstrip("/")
MUSICGRABBER_URL = os.environ.get(
    "MUSICGRABBER_URL",
    "http://musicgrabber-internal.media.svc.cluster.local:8080",
).rstrip("/")
ARR_APPS = {
    "sonarr": (
        os.environ.get(
            "SONARR_URL", "http://sonarr-internal.media.svc.cluster.local:8989"
        ).rstrip("/"),
        os.environ.get("SONARR_API_KEY", "").strip(),
    ),
    "radarr": (
        os.environ.get(
            "RADARR_URL", "http://radarr-internal.media.svc.cluster.local:7878"
        ).rstrip("/"),
        os.environ.get("RADARR_API_KEY", "").strip(),
    ),
}
SEERR_API_KEY = os.environ.get("SEERR_API_KEY", "").strip()
MEDIA_API_TOKEN = os.environ.get("MEDIA_API_TOKEN", "").strip()


class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def text(value: Any, limit: int = 300) -> str | None:
    if value is None:
        return None
    return str(value)[:limit]


def integer(value: Any, label: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be an integer") from exc


def bounded(value: Any, label: str, default: int = 20) -> int:
    if value in (None, ""):
        return default
    result = integer(value, label)
    if result < 1 or result > MAX_RESULTS:
        raise ApiError(
            HTTPStatus.BAD_REQUEST, f"{label} must be between 1 and {MAX_RESULTS}"
        )
    return result


def redact(value: Any) -> str:
    message = str(value)
    for secret in (
        MEDIA_API_TOKEN,
        SEERR_API_KEY,
        *(key for _, key in ARR_APPS.values()),
    ):
        if secret:
            message = message.replace(secret, "[REDACTED]")
    return message[:500]


class RefStore:
    def __init__(self) -> None:
        self._values: dict[str, tuple[float, str, Any]] = {}
        self._lock = threading.Lock()

    def issue(self, kind: str, value: Any) -> str:
        now = time.time()
        token = f"{kind[:3]}_{secrets.token_urlsafe(9)}"
        with self._lock:
            self._prune(now)
            if len(self._values) >= 1024:
                oldest = min(self._values, key=lambda item: self._values[item][0])
                self._values.pop(oldest, None)
            self._values[token] = (now + REF_TTL_SECONDS, kind, value)
        return token

    def resolve(self, token: Any, kinds: set[str]) -> Any:
        if not isinstance(token, str) or not token:
            raise ApiError(HTTPStatus.BAD_REQUEST, "a result reference is required")
        now = time.time()
        with self._lock:
            self._prune(now)
            stored = self._values.get(token)
        if stored is None or stored[1] not in kinds:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "reference is invalid or expired; repeat the corresponding search",
            )
        return stored[2]

    def _prune(self, now: float) -> None:
        for token, (expires, _, _) in list(self._values.items()):
            if expires <= now:
                self._values.pop(token, None)


REFS = RefStore()


def decode(payload: bytes) -> Any:
    if not payload:
        return {"ok": True}
    decoded = payload.decode("utf-8", errors="replace")
    try:
        return json.loads(decoded)
    except json.JSONDecodeError:
        return {"text": decoded[:4096]}


def upstream_request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    query: dict[str, Any] | None = None,
    body: Any = None,
    timeout: int = 45,
) -> Any:
    if query:
        cleaned = {key: value for key, value in query.items() if value is not None}
        if cleaned:
            url += ("&" if "?" in url else "?") + urlencode(cleaned, doseq=True)
    data = None if body is None else json.dumps(body).encode()
    request = Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/json",
            **({"Content-Type": "application/json"} if data is not None else {}),
            **(headers or {}),
        },
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return decode(response.read())
    except HTTPError as exc:
        detail = decode(exc.read(4096))
        raise ApiError(
            HTTPStatus.BAD_GATEWAY,
            f"upstream returned HTTP {exc.code}: {redact(detail)}",
        ) from exc
    except (URLError, TimeoutError) as exc:
        raise ApiError(
            HTTPStatus.BAD_GATEWAY, f"upstream request failed: {redact(exc)}"
        ) from exc


def seerr(method: str, path: str, **kwargs: Any) -> Any:
    if not SEERR_API_KEY:
        raise ApiError(HTTPStatus.SERVICE_UNAVAILABLE, "Seerr access is not configured")
    return upstream_request(
        method,
        f"{SEERR_URL}{path}",
        headers={"X-Api-Key": SEERR_API_KEY},
        **kwargs,
    )


def musicgrabber(method: str, path: str, **kwargs: Any) -> Any:
    return upstream_request(method, f"{MUSICGRABBER_URL}{path}", **kwargs)


def arr(app: str, method: str, path: str, **kwargs: Any) -> Any:
    if app not in ARR_APPS:
        raise ApiError(HTTPStatus.BAD_REQUEST, "app must be sonarr or radarr")
    base, key = ARR_APPS[app]
    if not key:
        raise ApiError(
            HTTPStatus.SERVICE_UNAVAILABLE, f"{app} access is not configured"
        )
    return upstream_request(
        method,
        f"{base}{path}",
        headers={"X-Api-Key": key},
        **kwargs,
    )


def quality_name(value: Any) -> str | None:
    if not isinstance(value, dict):
        return text(value)
    quality = value.get("quality")
    if isinstance(quality, dict):
        return text(quality.get("name"))
    return text(value.get("name"))


def custom_formats(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [
        str(item.get("name"))
        for item in value
        if isinstance(item, dict) and item.get("name")
    ]


def normalize_seerr_result(item: dict[str, Any]) -> dict[str, Any]:
    media_type = item.get("mediaType")
    title = item.get("title") if media_type == "movie" else item.get("name")
    date = (
        item.get("releaseDate") if media_type == "movie" else item.get("firstAirDate")
    )
    media = item.get("mediaInfo") if isinstance(item.get("mediaInfo"), dict) else {}
    return {
        "ref": REFS.issue(
            "seerr",
            {"mediaType": media_type, "mediaId": item.get("id"), "title": title},
        ),
        "type": media_type,
        "title": text(title),
        "year": str(date)[:4] if date else None,
        "tmdbId": item.get("id"),
        "status": media.get("status"),
        "requests": len(media.get("requests") or []),
        "overview": text(item.get("overview"), 500),
    }


def normalize_request(item: dict[str, Any]) -> dict[str, Any]:
    media = item.get("media") if isinstance(item.get("media"), dict) else {}
    seasons = item.get("seasons") if isinstance(item.get("seasons"), list) else []
    return {
        "id": item.get("id"),
        "type": item.get("type") or media.get("mediaType"),
        "status": item.get("status"),
        "mediaStatus": media.get("status"),
        "tmdbId": media.get("tmdbId"),
        "title": text(media.get("title") or media.get("name") or item.get("title")),
        "seasons": [
            season.get("seasonNumber") for season in seasons if isinstance(season, dict)
        ],
        "createdAt": item.get("createdAt"),
        "updatedAt": item.get("updatedAt"),
    }


def normalize_music_result(item: dict[str, Any], search_token: Any) -> dict[str, Any]:
    allowed = {
        key: item.get(key)
        for key in (
            "video_id",
            "title",
            "artist",
            "source",
            "source_url",
            "slskd_username",
            "slskd_filename",
            "slskd_size",
        )
    }
    allowed["artist"] = item.get("artist") or item.get("channel")
    allowed["search_token"] = search_token
    return {
        "ref": REFS.issue("music", allowed),
        "title": text(item.get("title")),
        "artist": text(item.get("artist") or item.get("channel")),
        "duration": item.get("duration"),
        "source": item.get("source"),
        "quality": item.get("quality"),
        "relevance": item.get("relevance_score"),
    }


def normalize_music_job(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": item.get("id"),
        "title": text(item.get("title")),
        "artist": text(item.get("artist")),
        "status": item.get("status"),
        "error": text(item.get("error"), 500),
        "source": item.get("source"),
        "type": item.get("download_type"),
        "createdAt": item.get("created_at"),
        "completedAt": item.get("completed_at"),
    }


def normalize_music_import(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": item.get("id") or item.get("import_id"),
        "status": item.get("status"),
        "totalTracks": item.get("total_tracks"),
        "searched": item.get("searched"),
        "queued": item.get("queued"),
        "failed": item.get("failed"),
        "skipped": item.get("skipped"),
        "error": text(item.get("error"), 500),
        "createdAt": item.get("created_at"),
        "completedAt": item.get("completed_at"),
    }


def normalize_queue(app: str, item: dict[str, Any]) -> dict[str, Any]:
    movie = item.get("movie") if isinstance(item.get("movie"), dict) else {}
    series = item.get("series") if isinstance(item.get("series"), dict) else {}
    episode = item.get("episode") if isinstance(item.get("episode"), dict) else {}
    title = movie.get("title") or series.get("title") or item.get("title")
    return {
        "app": app,
        "id": item.get("id"),
        "title": text(title),
        "episode": text(episode.get("title")),
        "season": episode.get("seasonNumber"),
        "episodeNumber": episode.get("episodeNumber"),
        "quality": quality_name(item.get("quality")),
        "customFormats": custom_formats(item.get("customFormats")),
        "customFormatScore": item.get("customFormatScore"),
        "status": item.get("status"),
        "trackedStatus": item.get("trackedDownloadStatus"),
        "trackedState": item.get("trackedDownloadState"),
        "messages": [
            text(message.get("message"), 500)
            for message in item.get("statusMessages") or []
            if isinstance(message, dict)
        ],
        "size": item.get("size"),
        "sizeleft": item.get("sizeleft"),
        "timeleft": item.get("timeleft"),
    }


def normalize_history(app: str, item: dict[str, Any]) -> dict[str, Any]:
    movie = item.get("movie") if isinstance(item.get("movie"), dict) else {}
    series = item.get("series") if isinstance(item.get("series"), dict) else {}
    episode = item.get("episode") if isinstance(item.get("episode"), dict) else {}
    data = item.get("data") if isinstance(item.get("data"), dict) else {}
    return {
        "app": app,
        "id": item.get("id"),
        "title": text(
            movie.get("title") or series.get("title") or item.get("sourceTitle")
        ),
        "episode": text(episode.get("title")),
        "season": episode.get("seasonNumber"),
        "episodeNumber": episode.get("episodeNumber"),
        "eventType": item.get("eventType"),
        "quality": quality_name(item.get("quality")),
        "customFormats": custom_formats(item.get("customFormats")),
        "customFormatScore": item.get("customFormatScore"),
        "date": item.get("date"),
        "sourceTitle": text(item.get("sourceTitle"), 500),
        "message": text(data.get("message") or data.get("reason"), 500),
    }


def normalize_movie(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "ref": REFS.issue("radarr-item", {"app": "radarr", "id": item.get("id")}),
        "id": item.get("id"),
        "title": text(item.get("title")),
        "year": item.get("year"),
        "status": item.get("status"),
        "monitored": item.get("monitored"),
        "qualityProfileId": item.get("qualityProfileId"),
        "hasFile": item.get("hasFile"),
        "sizeOnDisk": (item.get("statistics") or {}).get("sizeOnDisk"),
        "tmdbId": item.get("tmdbId"),
    }


def normalize_series(item: dict[str, Any]) -> dict[str, Any]:
    stats = item.get("statistics") if isinstance(item.get("statistics"), dict) else {}
    return {
        "ref": REFS.issue("sonarr-series", {"app": "sonarr", "id": item.get("id")}),
        "id": item.get("id"),
        "title": text(item.get("title")),
        "year": item.get("year"),
        "status": item.get("status"),
        "monitored": item.get("monitored"),
        "qualityProfileId": item.get("qualityProfileId"),
        "seriesType": item.get("seriesType"),
        "episodeCount": stats.get("episodeCount"),
        "episodeFileCount": stats.get("episodeFileCount"),
        "sizeOnDisk": stats.get("sizeOnDisk"),
        "tvdbId": item.get("tvdbId"),
    }


def normalize_episode(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "ref": REFS.issue(
            "sonarr-episode",
            {"app": "sonarr", "id": item.get("id"), "seriesId": item.get("seriesId")},
        ),
        "id": item.get("id"),
        "title": text(item.get("title")),
        "season": item.get("seasonNumber"),
        "episodeNumber": item.get("episodeNumber"),
        "airDate": item.get("airDateUtc") or item.get("airDate"),
        "monitored": item.get("monitored"),
        "hasFile": item.get("hasFile"),
    }


def normalize_release(app: str, item: dict[str, Any]) -> dict[str, Any]:
    return {
        "ref": REFS.issue("arr-release", {"app": app, "release": item}),
        "title": text(item.get("title"), 500),
        "indexer": text(item.get("indexer")),
        "protocol": item.get("protocol"),
        "quality": quality_name(item.get("quality")),
        "customFormats": custom_formats(item.get("customFormats")),
        "customFormatScore": item.get("customFormatScore"),
        "size": item.get("size"),
        "ageHours": item.get("ageHours"),
        "seeders": item.get("seeders"),
        "peers": item.get("peers"),
        "rejected": item.get("rejected"),
        "rejections": [text(value, 300) for value in item.get("rejections") or []],
        "downloadAllowed": item.get("downloadAllowed"),
    }


def records(payload: Any, *candidate_keys: str) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        values = []
        for key in (*candidate_keys, "records", "results"):
            if isinstance(payload.get(key), list):
                values = payload[key]
                break
    else:
        values = payload
    return [item for item in values or [] if isinstance(item, dict)]


class Routes:
    @staticmethod
    def status() -> dict[str, Any]:
        checks: dict[str, Any] = {}
        targets = {
            "seerr": lambda: seerr("GET", "/status"),
            "musicgrabber": lambda: musicgrabber("GET", "/api/auth/me"),
            "sonarr": lambda: arr("sonarr", "GET", "/ping"),
            "radarr": lambda: arr("radarr", "GET", "/ping"),
        }
        for name, check in targets.items():
            try:
                check()
                checks[name] = {"ok": True}
            except Exception as exc:
                checks[name] = {"ok": False, "error": redact(exc)}
        return {"ok": all(item["ok"] for item in checks.values()), "services": checks}

    @staticmethod
    def search(query: dict[str, list[str]]) -> dict[str, Any]:
        term = (query.get("q") or [""])[0].strip()
        if not term or len(term) > 200:
            raise ApiError(HTTPStatus.BAD_REQUEST, "q must contain 1 to 200 characters")
        media_type = (query.get("type") or ["all"])[0]
        if media_type not in {"all", "movie", "tv"}:
            raise ApiError(HTTPStatus.BAD_REQUEST, "type must be all, movie, or tv")
        limit = bounded((query.get("limit") or [None])[0], "limit", 10)
        payload = seerr("GET", "/search", query={"query": term, "page": 1})
        values = []
        for item in payload.get("results") or []:
            if not isinstance(item, dict) or item.get("mediaType") not in {
                "movie",
                "tv",
            }:
                continue
            if media_type != "all" and item.get("mediaType") != media_type:
                continue
            values.append(normalize_seerr_result(item))
            if len(values) >= limit:
                break
        return {"results": values}

    @staticmethod
    def request(body: dict[str, Any]) -> dict[str, Any]:
        selected = REFS.resolve(body.get("ref"), {"seerr"})
        payload = {"mediaType": selected["mediaType"], "mediaId": selected["mediaId"]}
        if selected["mediaType"] == "tv":
            seasons = body.get("seasons", "all")
            if seasons != "all":
                if not isinstance(seasons, list) or not seasons:
                    raise ApiError(
                        HTTPStatus.BAD_REQUEST,
                        "seasons must be all or a non-empty list",
                    )
                seasons = sorted({integer(value, "season") for value in seasons})
                if any(value < 0 for value in seasons):
                    raise ApiError(
                        HTTPStatus.BAD_REQUEST, "season numbers cannot be negative"
                    )
            payload["seasons"] = seasons
        result = seerr("POST", "/request", body=payload)
        audit("request", {"type": selected["mediaType"], "id": selected["mediaId"]})
        return normalize_request(result)

    @staticmethod
    def requests(query: dict[str, list[str]]) -> dict[str, Any]:
        limit = bounded((query.get("limit") or [None])[0], "limit", 20)
        status = (query.get("status") or ["all"])[0]
        allowed = {
            "all",
            "approved",
            "available",
            "pending",
            "processing",
            "unavailable",
            "failed",
            "deleted",
            "completed",
        }
        if status not in allowed:
            raise ApiError(HTTPStatus.BAD_REQUEST, "unsupported request status")
        payload = seerr(
            "GET",
            "/request",
            query={
                "take": limit,
                "skip": 0,
                "filter": status,
                "sort": "added",
                "sortDirection": "desc",
            },
        )
        return {
            "pageInfo": payload.get("pageInfo"),
            "results": [normalize_request(item) for item in records(payload)[:limit]],
        }

    @staticmethod
    def request_show(request_id: str) -> dict[str, Any]:
        return normalize_request(
            seerr("GET", f"/request/{integer(request_id, 'request id')}")
        )

    @staticmethod
    def music_search(body: dict[str, Any]) -> dict[str, Any]:
        term = str(body.get("query") or "").strip()
        if not term or len(term) > 200:
            raise ApiError(
                HTTPStatus.BAD_REQUEST, "query must contain 1 to 200 characters"
            )
        limit = bounded(body.get("limit"), "limit", 10)
        source = str(body.get("source") or "all")
        if not re.fullmatch(r"[a-z0-9_-]{1,40}", source):
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid music source")
        payload = musicgrabber(
            "POST",
            "/api/search",
            body={"query": term, "limit": limit, "source": source},
        )
        token = payload.get("search_token")
        return {
            "results": [
                normalize_music_result(item, token) for item in records(payload)[:limit]
            ],
            "unavailableSources": [
                {"id": item.get("id"), "reason": text(item.get("reason"), 300)}
                for item in payload.get("unavailable_sources") or []
                if isinstance(item, dict)
            ],
        }

    @staticmethod
    def music_download(body: dict[str, Any]) -> dict[str, Any]:
        selected = REFS.resolve(body.get("ref"), {"music"})
        payload = {
            "video_id": selected.get("video_id"),
            "title": selected.get("title"),
            "artist": selected.get("artist"),
            "source": selected.get("source") or "youtube",
            "source_url": selected.get("source_url"),
            "search_token": selected.get("search_token"),
            "slskd_username": selected.get("slskd_username"),
            "slskd_filename": selected.get("slskd_filename"),
            "slskd_size": selected.get("slskd_size"),
            "download_type": "single",
        }
        result = musicgrabber("POST", "/api/download", body=payload)
        audit(
            "music-download",
            {"source": payload["source"], "video_id": payload["video_id"]},
        )
        result = result if isinstance(result, dict) else {}
        return {
            "id": result.get("job_id") or result.get("id"),
            "status": result.get("status") or "queued",
            "title": text(selected.get("title")),
            "artist": text(selected.get("artist")),
            "source": selected.get("source"),
        }

    @staticmethod
    def music_sources() -> dict[str, Any]:
        payload = musicgrabber("GET", "/api/sources")
        return {
            "results": [
                {
                    "id": text(item.get("id"), 40),
                    "label": text(item.get("label")),
                    "enabled": bool(item.get("enabled")),
                }
                for item in records(payload, "sources")
            ]
        }

    @staticmethod
    def artist_search(query: dict[str, list[str]]) -> dict[str, Any]:
        term = (query.get("q") or [""])[0].strip()
        if not term or len(term) > 200:
            raise ApiError(HTTPStatus.BAD_REQUEST, "q must contain 1 to 200 characters")
        payload = musicgrabber("GET", "/api/albums/search-artist", query={"q": term})
        values = payload.get("artists") if isinstance(payload, dict) else payload
        results = []
        for item in values or []:
            if not isinstance(item, dict):
                continue
            results.append(
                {
                    "ref": REFS.issue(
                        "artist", {"mbid": item.get("mbid"), "name": item.get("name")}
                    ),
                    "name": text(item.get("name")),
                    "disambiguation": text(item.get("disambiguation")),
                    "score": item.get("score"),
                }
            )
        return {"results": results[:10]}

    @staticmethod
    def albums(query: dict[str, list[str]]) -> dict[str, Any]:
        selected = REFS.resolve((query.get("ref") or [None])[0], {"artist"})
        payload = musicgrabber(
            "GET", f"/api/albums/artist/{quote(str(selected['mbid']), safe='')}/albums"
        )
        values = payload.get("albums") if isinstance(payload, dict) else payload
        return {
            "artist": selected.get("name"),
            "results": [
                {
                    "ref": REFS.issue(
                        "album",
                        {
                            "artist": selected.get("name"),
                            "album_title": item.get("title"),
                            "release_mbid": item.get("release_mbid"),
                        },
                    ),
                    "title": text(item.get("title")),
                    "year": item.get("year"),
                }
                for item in values or []
                if isinstance(item, dict)
            ][:MAX_RESULTS],
        }

    @staticmethod
    def album_download(body: dict[str, Any]) -> dict[str, Any]:
        selected = REFS.resolve(body.get("ref"), {"album"})
        result = musicgrabber(
            "POST", "/api/albums/download", body={**selected, "make_m3u": False}
        )
        audit("album-download", {"release_mbid": selected.get("release_mbid")})
        result = result if isinstance(result, dict) else {}
        return {
            "importId": result.get("import_id") or result.get("id"),
            "status": result.get("status") or "queued",
            "artist": text(selected.get("artist")),
            "album": text(selected.get("album_title")),
        }

    @staticmethod
    def music_jobs(query: dict[str, list[str]]) -> dict[str, Any]:
        limit = bounded((query.get("limit") or [None])[0], "limit", 20)
        status = (query.get("status") or [None])[0]
        payload = musicgrabber(
            "GET", "/api/jobs", query={"limit": min(MAX_RESULTS, limit * 3)}
        )
        values = [normalize_music_job(item) for item in records(payload, "jobs")]
        if status:
            values = [item for item in values if item.get("status") == status]
        return {"results": values[:limit]}

    @staticmethod
    def music_job(job_id: str) -> dict[str, Any]:
        return normalize_music_job(
            musicgrabber("GET", f"/api/jobs/{quote(job_id, safe='')}")
        )

    @staticmethod
    def album_jobs(query: dict[str, list[str]]) -> dict[str, Any]:
        limit = bounded((query.get("limit") or [None])[0], "limit", 10)
        payload = musicgrabber("GET", "/api/bulk-imports", query={"limit": limit})
        return {
            "results": [
                normalize_music_import(item)
                for item in records(payload, "imports")[:limit]
            ]
        }

    @staticmethod
    def album_job(import_id: str) -> dict[str, Any]:
        payload = musicgrabber(
            "GET", f"/api/bulk-import/{quote(import_id, safe='')}/status"
        )
        return normalize_music_import(payload)

    @staticmethod
    def arr_queue(query: dict[str, list[str]]) -> dict[str, Any]:
        app = (query.get("app") or ["sonarr"])[0]
        limit = bounded((query.get("limit") or [None])[0], "limit", 20)
        payload = arr(
            app,
            "GET",
            "/api/v3/queue",
            query={
                "page": 1,
                "pageSize": limit,
                "sortKey": "timeleft",
                "sortDirection": "ascending",
                "includeSeries": app == "sonarr",
                "includeEpisode": app == "sonarr",
                "includeMovie": app == "radarr",
            },
        )
        return {
            "app": app,
            "total": payload.get("totalRecords"),
            "results": [
                normalize_queue(app, item) for item in records(payload)[:limit]
            ],
        }

    @staticmethod
    def arr_history(query: dict[str, list[str]]) -> dict[str, Any]:
        app = (query.get("app") or ["sonarr"])[0]
        limit = bounded((query.get("limit") or [None])[0], "limit", 20)
        search = (query.get("query") or [""])[0].casefold()
        payload = arr(
            app,
            "GET",
            "/api/v3/history",
            query={
                "page": 1,
                "pageSize": min(MAX_RESULTS, limit * 2),
                "sortKey": "date",
                "sortDirection": "descending",
                "includeSeries": app == "sonarr",
                "includeEpisode": app == "sonarr",
                "includeMovie": app == "radarr",
            },
        )
        values = [normalize_history(app, item) for item in records(payload)]
        if search:
            values = [
                item
                for item in values
                if search in str(item.get("title") or "").casefold()
                or search in str(item.get("sourceTitle") or "").casefold()
            ]
        return {"app": app, "results": values[:limit]}

    @staticmethod
    def arr_missing(query: dict[str, list[str]]) -> dict[str, Any]:
        app = (query.get("app") or ["sonarr"])[0]
        limit = bounded((query.get("limit") or [None])[0], "limit", 20)
        payload = arr(
            app,
            "GET",
            "/api/v3/wanted/missing",
            query={
                "page": 1,
                "pageSize": limit,
                "sortKey": "airDateUtc" if app == "sonarr" else "physicalRelease",
                "sortDirection": "descending",
                "includeSeries": app == "sonarr",
                "includeImages": False,
                "monitored": True,
            },
        )
        results = []
        for item in records(payload)[:limit]:
            if app == "sonarr":
                series = (
                    item.get("series") if isinstance(item.get("series"), dict) else {}
                )
                normalized = normalize_episode(item)
                normalized["series"] = text(series.get("title"))
            else:
                normalized = normalize_movie(item)
            results.append(normalized)
        return {"app": app, "total": payload.get("totalRecords"), "results": results}

    @staticmethod
    def arr_lookup(query: dict[str, list[str]]) -> dict[str, Any]:
        app = (query.get("app") or ["sonarr"])[0]
        term = (query.get("q") or [""])[0].strip()
        limit = bounded((query.get("limit") or [None])[0], "limit", 10)
        if not term or len(term) > 200:
            raise ApiError(HTTPStatus.BAD_REQUEST, "q must contain 1 to 200 characters")
        payload = arr(
            app, "GET", "/api/v3/series" if app == "sonarr" else "/api/v3/movie"
        )
        values = [
            item
            for item in payload
            if isinstance(item, dict)
            and term.casefold() in str(item.get("title") or "").casefold()
        ]
        normalizer = normalize_series if app == "sonarr" else normalize_movie
        return {"app": app, "results": [normalizer(item) for item in values[:limit]]}

    @staticmethod
    def arr_item(query: dict[str, list[str]]) -> dict[str, Any]:
        selected = REFS.resolve(
            (query.get("ref") or [None])[0],
            {"sonarr-series", "sonarr-episode", "radarr-item"},
        )
        app = selected["app"]
        if app == "radarr":
            return normalize_movie(arr(app, "GET", f"/api/v3/movie/{selected['id']}"))
        if "seriesId" in selected:
            return normalize_episode(
                arr(app, "GET", f"/api/v3/episode/{selected['id']}")
            )
        return normalize_series(arr(app, "GET", f"/api/v3/series/{selected['id']}"))

    @staticmethod
    def episodes(query: dict[str, list[str]]) -> dict[str, Any]:
        selected = REFS.resolve((query.get("ref") or [None])[0], {"sonarr-series"})
        season = (query.get("season") or [None])[0]
        payload = arr(
            "sonarr",
            "GET",
            "/api/v3/episode",
            query={
                "seriesId": selected["id"],
                "seasonNumber": integer(season, "season")
                if season is not None
                else None,
            },
        )
        return {
            "results": [
                normalize_episode(item) for item in payload if isinstance(item, dict)
            ][:MAX_RESULTS]
        }

    @staticmethod
    def profiles(query: dict[str, list[str]]) -> dict[str, Any]:
        app = (query.get("app") or ["sonarr"])[0]
        payload = arr(app, "GET", "/api/v3/qualityprofile")
        return {
            "app": app,
            "results": [
                {
                    "id": item.get("id"),
                    "name": text(item.get("name")),
                    "cutoff": item.get("cutoff"),
                    "upgradeAllowed": item.get("upgradeAllowed"),
                    "minFormatScore": item.get("minFormatScore"),
                    "cutoffFormatScore": item.get("cutoffFormatScore"),
                }
                for item in payload
                if isinstance(item, dict)
            ],
        }

    @staticmethod
    def formats(query: dict[str, list[str]]) -> dict[str, Any]:
        app = (query.get("app") or ["sonarr"])[0]
        payload = arr(app, "GET", "/api/v3/customformat")
        return {
            "app": app,
            "results": [
                {
                    "id": item.get("id"),
                    "name": text(item.get("name")),
                    "includeInRenaming": item.get("includeCustomFormatWhenRenaming"),
                }
                for item in payload
                if isinstance(item, dict)
            ],
        }

    @staticmethod
    def releases(query: dict[str, list[str]]) -> dict[str, Any]:
        selected = REFS.resolve(
            (query.get("ref") or [None])[0],
            {"sonarr-series", "sonarr-episode", "radarr-item"},
        )
        app = selected["app"]
        params = (
            {"movieId": selected["id"]}
            if app == "radarr"
            else (
                {"episodeId": selected["id"]}
                if "seriesId" in selected
                else {"seriesId": selected["id"]}
            )
        )
        payload = arr(app, "GET", "/api/v3/release", query=params, timeout=120)
        values = [
            normalize_release(app, item) for item in payload if isinstance(item, dict)
        ]
        values.sort(
            key=lambda item: (
                bool(item.get("rejected")),
                -(item.get("customFormatScore") or 0),
            )
        )
        return {"app": app, "results": values[:MAX_RESULTS]}

    @staticmethod
    def diagnose(query: dict[str, list[str]]) -> dict[str, Any]:
        token = (query.get("ref") or [None])[0]
        selected = REFS.resolve(
            token, {"sonarr-series", "sonarr-episode", "radarr-item"}
        )
        app = selected["app"]
        item = Routes.arr_item({"ref": [token]})
        parent = None
        if app == "sonarr" and "seriesId" in selected:
            parent = normalize_series(
                arr(app, "GET", f"/api/v3/series/{selected['seriesId']}")
            )
        profile_id = (parent or item).get("qualityProfileId")
        profiles = Routes.profiles({"app": [app]})["results"]
        profile = next(
            (entry for entry in profiles if entry.get("id") == profile_id), None
        )
        history_query = {"app": [app], "limit": ["10"]}
        history = Routes.arr_history(history_query)["results"]
        title = str((parent or item).get("title") or "").casefold()
        history = [
            entry
            for entry in history
            if title and title in str(entry.get("title") or "").casefold()
        ][:10]
        return {
            "app": app,
            "item": item,
            "series": parent,
            "profile": profile,
            "history": history,
            "next": "run media releases with this item reference to inspect current candidates",
        }

    @staticmethod
    def search_item(body: dict[str, Any]) -> dict[str, Any]:
        selected = REFS.resolve(
            body.get("ref"), {"sonarr-series", "sonarr-episode", "radarr-item"}
        )
        app = selected["app"]
        if app == "radarr":
            command = {"name": "MoviesSearch", "movieIds": [selected["id"]]}
        elif "seriesId" in selected:
            command = {"name": "EpisodeSearch", "episodeIds": [selected["id"]]}
        else:
            command = {"name": "SeriesSearch", "seriesId": selected["id"]}
        result = arr(app, "POST", "/api/v3/command", body=command)
        audit("search-item", {"app": app, "id": selected["id"]})
        return {
            "app": app,
            "commandId": result.get("id"),
            "status": result.get("status"),
            "name": result.get("name"),
        }

    @staticmethod
    def grab(body: dict[str, Any]) -> dict[str, Any]:
        selected = REFS.resolve(body.get("ref"), {"arr-release"})
        release = selected["release"]
        if release.get("rejected") or release.get("downloadAllowed") is False:
            raise ApiError(
                HTTPStatus.CONFLICT,
                "the selected release is rejected or not downloadable",
            )
        result = arr(selected["app"], "POST", "/api/v3/release", body=release)
        audit(
            "grab-release",
            {"app": selected["app"], "title": text(release.get("title"), 200)},
        )
        return {
            "app": selected["app"],
            "accepted": True,
            "title": text(release.get("title"), 500),
            "downloadId": result.get("downloadId")
            if isinstance(result, dict)
            else None,
        }


def audit(action: str, details: dict[str, Any]) -> None:
    print(
        json.dumps(
            {"event": "hermes-media-action", "action": action, "details": details},
            separators=(",", ":"),
        ),
        flush=True,
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "hermes-media-api/1"

    def do_GET(self) -> None:
        self._dispatch("GET")

    def do_POST(self) -> None:
        self._dispatch("POST")

    def do_PUT(self) -> None:
        self._method_not_allowed()

    def do_PATCH(self) -> None:
        self._method_not_allowed()

    def do_DELETE(self) -> None:
        self._method_not_allowed()

    def log_message(self, fmt: str, *args: Any) -> None:
        print(
            json.dumps(
                {
                    "event": "http",
                    "client": self.client_address[0],
                    "message": fmt % args,
                },
                separators=(",", ":"),
            ),
            file=sys.stderr,
        )

    def _dispatch(self, method: str) -> None:
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/health" and method == "GET":
                self._json(HTTPStatus.OK, {"ok": True})
                return
            self._authenticate()
            query = parse_qs(parsed.query)
            body = self._body() if method == "POST" else {}

            get_routes = {
                "/v1/status": lambda: Routes.status(),
                "/v1/search": lambda: Routes.search(query),
                "/v1/requests": lambda: Routes.requests(query),
                "/v1/artist-search": lambda: Routes.artist_search(query),
                "/v1/music-sources": lambda: Routes.music_sources(),
                "/v1/albums": lambda: Routes.albums(query),
                "/v1/music-jobs": lambda: Routes.music_jobs(query),
                "/v1/album-jobs": lambda: Routes.album_jobs(query),
                "/v1/queue": lambda: Routes.arr_queue(query),
                "/v1/history": lambda: Routes.arr_history(query),
                "/v1/missing": lambda: Routes.arr_missing(query),
                "/v1/lookup": lambda: Routes.arr_lookup(query),
                "/v1/item": lambda: Routes.arr_item(query),
                "/v1/episodes": lambda: Routes.episodes(query),
                "/v1/profiles": lambda: Routes.profiles(query),
                "/v1/formats": lambda: Routes.formats(query),
                "/v1/releases": lambda: Routes.releases(query),
                "/v1/diagnose": lambda: Routes.diagnose(query),
            }
            post_routes = {
                "/v1/request": lambda: Routes.request(body),
                "/v1/music-search": lambda: Routes.music_search(body),
                "/v1/music-download": lambda: Routes.music_download(body),
                "/v1/album-download": lambda: Routes.album_download(body),
                "/v1/search-item": lambda: Routes.search_item(body),
                "/v1/grab": lambda: Routes.grab(body),
            }
            if method == "GET" and parsed.path.startswith("/v1/request/"):
                result = Routes.request_show(parsed.path.rsplit("/", 1)[-1])
            elif method == "GET" and parsed.path.startswith("/v1/music-job/"):
                result = Routes.music_job(parsed.path.rsplit("/", 1)[-1])
            elif method == "GET" and parsed.path.startswith("/v1/album-job/"):
                result = Routes.album_job(parsed.path.rsplit("/", 1)[-1])
            else:
                route = (get_routes if method == "GET" else post_routes).get(
                    parsed.path
                )
                if route is None:
                    raise ApiError(HTTPStatus.NOT_FOUND, "route not found")
                result = route()
            self._json(HTTPStatus.OK, result)
        except ApiError as exc:
            self._json(exc.status, {"error": exc.message})
        except Exception as exc:
            print(f"unhandled request error: {redact(exc)}", file=sys.stderr)
            self._json(
                HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "internal server error"}
            )

    def _authenticate(self) -> None:
        if not MEDIA_API_TOKEN:
            raise ApiError(
                HTTPStatus.SERVICE_UNAVAILABLE, "media API token is not configured"
            )
        authorization = self.headers.get("Authorization", "")
        candidate = (
            authorization[7:].strip() if authorization.startswith("Bearer ") else ""
        )
        if not candidate or not hmac.compare_digest(candidate, MEDIA_API_TOKEN):
            raise ApiError(HTTPStatus.UNAUTHORIZED, "authentication required")

    def _body(self) -> dict[str, Any]:
        raw_length = self.headers.get("Content-Length", "0")
        length = integer(raw_length, "Content-Length")
        if length < 0 or length > MAX_BODY:
            raise ApiError(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "request body is too large"
            )
        try:
            value = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError as exc:
            raise ApiError(
                HTTPStatus.BAD_REQUEST, "request body must be valid JSON"
            ) from exc
        if not isinstance(value, dict):
            raise ApiError(HTTPStatus.BAD_REQUEST, "request body must be a JSON object")
        return value

    def _method_not_allowed(self) -> None:
        self._json(HTTPStatus.METHOD_NOT_ALLOWED, {"error": "method not allowed"})

    def _json(self, status: int, value: Any) -> None:
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    missing = [
        name
        for name, value in {
            "MEDIA_API_TOKEN": MEDIA_API_TOKEN,
            "SEERR_API_KEY": SEERR_API_KEY,
            "SONARR_API_KEY": ARR_APPS["sonarr"][1],
            "RADARR_API_KEY": ARR_APPS["radarr"][1],
        }.items()
        if not value
    ]
    if missing:
        print(f"missing required configuration: {', '.join(missing)}", file=sys.stderr)
        return 1
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print(json.dumps({"event": "startup", "port": 8080}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
