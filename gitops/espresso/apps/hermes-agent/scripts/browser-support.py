#!/usr/bin/env python3
"""Low-level Chromium CDP helpers for Hermes browser operations."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, NamedTuple
from urllib.parse import urlparse

import requests
from websocket import create_connection


_SAFE_NAME = re.compile(r"[^A-Za-z0-9_.-]+")
_CHALLENGE_PATTERNS = [
    ("captcha", re.compile(r"\bcaptcha\b", re.I)),
    ("verification", re.compile(r"\b(?:verify|verification|verified)\b", re.I)),
    ("checking_browser", re.compile(r"checking your browser|just a moment", re.I)),
    ("cloudflare", re.compile(r"\bcloudflare\b", re.I)),
    ("unusual_traffic", re.compile(r"unusual traffic|too many requests|rate limit", re.I)),
    ("robot_check", re.compile(r"are you human|are you a robot|press and hold", re.I)),
    ("challenge_frame", re.compile(r"challenge|turnstile|recaptcha|hcaptcha", re.I)),
]
_MAX_TEXT_SNIPPET = 4000
_MOUSE_BUTTON_MASKS = {"left": 1, "right": 2, "middle": 4}
_EXPECTED_EXTENSION_PROBES = (
    {
        "id": "ddkjiahejlhfcafbddmgiahcphecmpfh",
        "name": "uBlock Origin Lite",
        "probe_url": "chrome-extension://ddkjiahejlhfcafbddmgiahcphecmpfh/popup.html",
        "requires_enabled_rulesets": True,
    },
)


def compact(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def safe_text(value: Any) -> str:
    return str(value).strip()[:500]


def safe_slug(value: str, fallback: str = "default") -> str:
    return _SAFE_NAME.sub("_", value.strip())[:80] or fallback


def browser_files_root() -> Path:
    return Path(os.environ.get("BROWSER_FILES_ROOT", "/opt/browser-files")).resolve()


def browser_profile_root() -> Path:
    return Path(os.environ.get("BROWSER_PROFILE_ROOT", "/opt/browser")).resolve()


def browser_policy_root() -> Path:
    return Path(
        os.environ.get("BROWSER_POLICY_ROOT", "/etc/chromium/policies/managed")
    ).resolve()


def browser_supervisor_root() -> Path:
    return browser_files_root() / "browser-supervisor"


def browser_view_url() -> str:
    return os.environ.get(
        "BROWSER_VIEW_URL",
        "https://browser.asgard.michaelbrusegard.com/vnc.html"
        "?autoconnect=true&resize=scale&view_only=false&reconnect=true",
    )


def resolve_local_path(path: Path) -> Path:
    """Resolve any path visible to the agent process without a helper allowlist."""
    return path.expanduser().resolve()


def browser_bucket(bucket: str) -> Path:
    destination = browser_files_root() / bucket
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def session_bucket() -> Path:
    return browser_bucket("browser-sessions")


def event_bucket() -> Path:
    return browser_bucket("browser-session-events")


def session_path(task_id: str) -> Path:
    return session_bucket() / f"{safe_slug(task_id)}.json"


def event_path(task_id: str) -> Path:
    return event_bucket() / f"{safe_slug(task_id)}.jsonl"


def load_session_state(task_id: str) -> dict[str, Any]:
    payload = json.loads(session_path(task_id).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"invalid browser session metadata for task {task_id}")
    return payload


def list_session_states() -> list[dict[str, Any]]:
    sessions: list[dict[str, Any]] = []
    for candidate in sorted(session_bucket().glob("*.json")):
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            sessions.append(payload)
    return sessions


def load_session_events(task_id: str, limit: int = 50) -> list[dict[str, Any]]:
    payload: list[dict[str, Any]] = []
    candidate = event_path(task_id)
    if not candidate.exists():
        return payload
    for line in candidate.read_text(encoding="utf-8").splitlines()[-max(1, limit):]:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict):
            payload.append(record)
    return payload


def list_session_events(limit: int = 50) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for candidate in sorted(event_bucket().glob("*.jsonl")):
        for line in candidate.read_text(encoding="utf-8").splitlines()[-max(1, limit):]:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                events.append(record)
    return events[-max(1, limit):]


def resolve_target_id(target_id: str | None, task_id: str | None) -> str:
    if target_id:
        return target_id
    if not task_id:
        raise ValueError("provide a target_id or --task-id")
    session = load_session_state(task_id)
    resolved = str(session.get("active_target_id") or "")
    if not resolved:
        raise ValueError(f"task {task_id} has no active_target_id in browser session metadata")
    return resolved


def resolve_session_hint(target_id: str) -> list[str]:
    owners: list[str] = []
    for session in list_session_states():
        owned = [str(item) for item in session.get("owned_target_ids", [])]
        if target_id in owned:
            owners.append(str(session.get("task_id") or ""))
    return owners


def resolve_output_path(raw_path: str | None, bucket: str, suffix: str) -> Path:
    extension = suffix if suffix.startswith(".") else f".{suffix}"
    if raw_path:
        destination = resolve_local_path(Path(raw_path))
        if destination.name in {"", ".", ".."}:
            raise ValueError("output path must name a file")
        destination.parent.mkdir(parents=True, exist_ok=True)
        return destination
    return browser_bucket(bucket) / f"{uuid.uuid4().hex[:12]}{extension}"


def default_cdp_url() -> str:
    return os.environ.get("BROWSER_CDP_URL", "http://127.0.0.1:9222")


def normalize_http_cdp_base(raw_url: str) -> str:
    parsed = urlparse(raw_url)
    if parsed.scheme in {"ws", "wss"}:
        scheme = "https" if parsed.scheme == "wss" else "http"
        host = parsed.netloc
        path = parsed.path.rsplit("/", 2)[0]
        if path.endswith("/devtools"):
            path = path[: -len("/devtools")]
        return f"{scheme}://{host}{path}".rstrip("/")
    if parsed.scheme in {"http", "https"}:
        return raw_url.rstrip("/")
    raise ValueError(f"unsupported CDP URL scheme: {raw_url}")


def directory_size(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for entry in path.rglob("*"):
        try:
            if entry.is_file() and not entry.is_symlink():
                total += entry.stat().st_size
        except FileNotFoundError:
            continue
    return total


def load_json_file(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def extension_manifest_name(manifest_path: Path, manifest: dict[str, Any]) -> str:
    raw_name = str(manifest.get("name") or manifest_path.parents[1].name)
    message_match = re.fullmatch(r"__MSG_(.+)__", raw_name)
    if message_match is None:
        return raw_name
    message_key = message_match.group(1)
    default_locale = str(manifest.get("default_locale") or "en")
    for locale in dict.fromkeys((default_locale, "en", "en_US")):
        messages = load_json_file(
            manifest_path.parent / "_locales" / locale / "messages.json"
        )
        message = messages.get(message_key) if messages else None
        if isinstance(message, dict) and message.get("message"):
            return str(message["message"])
    return raw_name


def installed_profile_extensions(profile_root: Path) -> list[dict[str, Any]]:
    profile_directory = profile_root / "profile"
    extensions: list[dict[str, Any]] = []
    for manifest_path in sorted(
        profile_directory.glob("*/Extensions/*/*/manifest.json")
    ):
        manifest = load_json_file(manifest_path)
        if manifest is None:
            continue
        profile_name = manifest_path.parents[3].name
        extension_id = manifest_path.parents[1].name
        preferences = load_json_file(profile_directory / profile_name / "Preferences") or {}
        settings = preferences.get("extensions", {}).get("settings", {})
        preference = settings.get(extension_id, {}) if isinstance(settings, dict) else {}
        disable_reasons = (
            preference.get("disable_reasons", []) if isinstance(preference, dict) else []
        )
        state = preference.get("state") if isinstance(preference, dict) else None
        extensions.append(
            {
                "id": extension_id,
                "name": extension_manifest_name(manifest_path, manifest),
                "version": str(manifest.get("version") or manifest_path.parent.name),
                "profile": profile_name,
                "enabled_in_preferences": state != 0 and not disable_reasons,
                "disable_reasons": disable_reasons,
                "path": str(manifest_path.parent),
            }
        )
    return extensions


def probe_extension(
    client: "CDPClient", browser_websocket_url: str, extension: dict[str, Any]
) -> dict[str, Any]:
    extension_id = str(extension["id"])
    name = str(extension["name"])
    probe_url = str(extension["probe_url"])
    target_id: str | None = None
    result: dict[str, Any] = {
        "id": extension_id,
        "name": name,
        "probe_url": probe_url,
        "loaded": False,
        "healthy": False,
        "enabled_rulesets": [],
    }
    try:
        created = client.call(
            browser_websocket_url,
            "Target.createTarget",
            {"url": probe_url, "background": True},
        )
        target_id = str(created.get("targetId") or "")
        if not target_id:
            raise RuntimeError("Chromium did not return an extension probe target")

        probe_state: Any = None
        last_error: Exception | None = None
        for _ in range(30):
            try:
                probe_state = evaluate_expression(
                    client,
                    target_id,
                    """
                    (async () => {
                      const dnr = globalThis.chrome?.declarativeNetRequest;
                      const enabledRulesets = dnr?.getEnabledRulesets
                        ? await dnr.getEnabledRulesets()
                        : [];
                      return {
                        readyState: document.readyState,
                        title: document.title,
                        url: location.href,
                        runtimeId: globalThis.chrome?.runtime?.id || null,
                        enabledRulesets,
                      };
                    })()
                    """,
                )
                if (
                    isinstance(probe_state, dict)
                    and probe_state.get("readyState") == "complete"
                    and probe_state.get("runtimeId") == extension_id
                ):
                    break
            except (RuntimeError, ValueError) as exc:
                last_error = exc
            time.sleep(0.1)
        if not isinstance(probe_state, dict):
            raise RuntimeError(last_error or "extension probe did not return page state")

        enabled_rulesets = probe_state.get("enabledRulesets")
        if not isinstance(enabled_rulesets, list):
            enabled_rulesets = []
        loaded = probe_state.get("runtimeId") == extension_id
        requires_rulesets = bool(extension.get("requires_enabled_rulesets"))
        result.update(
            {
                "loaded": loaded,
                "healthy": loaded and (not requires_rulesets or bool(enabled_rulesets)),
                "title": safe_text(probe_state.get("title") or ""),
                "url": safe_text(probe_state.get("url") or ""),
                "enabled_rulesets": [safe_text(item) for item in enabled_rulesets],
            }
        )
        if not loaded:
            result["error"] = "extension runtime was unavailable"
        elif requires_rulesets and not enabled_rulesets:
            result["error"] = "extension loaded without enabled blocking rulesets"
    except Exception as exc:
        result["error"] = safe_text(exc)
    finally:
        if target_id:
            try:
                client.call(
                    browser_websocket_url,
                    "Target.closeTarget",
                    {"targetId": target_id},
                )
            except Exception as exc:
                result["close_error"] = safe_text(exc)
    return result


def probe_expected_extensions(
    client: "CDPClient", browser_websocket_url: str
) -> list[dict[str, Any]]:
    if not browser_websocket_url:
        return [
            {
                "id": extension["id"],
                "name": extension["name"],
                "probe_url": extension["probe_url"],
                "loaded": False,
                "healthy": False,
                "enabled_rulesets": [],
                "error": "CDP browser websocket is unavailable",
            }
            for extension in _EXPECTED_EXTENSION_PROBES
        ]
    return [
        probe_extension(client, browser_websocket_url, extension)
        for extension in _EXPECTED_EXTENSION_PROBES
    ]


def iso_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


class Target(NamedTuple):
    target_id: str
    title: str
    url: str
    type: str
    websocket_url: str


class CDPClient:
    def __init__(self, base_url: str) -> None:
        self.base_url = normalize_http_cdp_base(base_url)
        self._connections: dict[str, Any] = {}
        self._next_message_id = 1

    def _http_get(self, path: str) -> Any:
        response = requests.get(f"{self.base_url}{path}", timeout=10)
        response.raise_for_status()
        return response.json()

    def version(self) -> dict[str, Any]:
        payload = self._http_get("/json/version")
        return payload if isinstance(payload, dict) else {}

    def targets(self) -> list[Target]:
        payload = self._http_get("/json/list")
        targets: list[Target] = []
        for item in payload if isinstance(payload, list) else []:
            if not isinstance(item, dict):
                continue
            target_id = str(item.get("id") or item.get("targetId") or "")
            websocket_url = str(item.get("webSocketDebuggerUrl") or "")
            if not target_id or not websocket_url:
                continue
            targets.append(
                Target(
                    target_id=target_id,
                    title=str(item.get("title") or ""),
                    url=str(item.get("url") or ""),
                    type=str(item.get("type") or ""),
                    websocket_url=websocket_url,
                )
            )
        return targets

    def target(self, target_id: str) -> Target:
        for target in self.targets():
            if target.target_id == target_id:
                return target
        raise ValueError(f"target_id not found: {target_id}")

    def close(self) -> None:
        for connection in self._connections.values():
            try:
                connection.close()
            except Exception:
                pass
        self._connections.clear()

    def __del__(self) -> None:
        self.close()

    def call(self, websocket_url: str, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        message_id = self._next_message_id
        self._next_message_id += 1
        payload = {"id": message_id, "method": method, "params": params or {}}
        connection = self._connections.get(websocket_url)
        if connection is None:
            # Chromium rejects websocket-client's synthesized HTTP Origin unless
            # the browser is launched with a broad remote-allow-origins policy.
            # CDP is pod-local here, so omit Origin on this direct debugger link.
            connection = create_connection(websocket_url, timeout=15, suppress_origin=True)
            self._connections[websocket_url] = connection
        try:
            connection.send(json.dumps(payload))
            while True:
                raw = connection.recv()
                message = json.loads(raw)
                if message.get("id") != message_id:
                    continue
                if "error" in message:
                    error = message["error"]
                    raise RuntimeError(
                        f"{method} failed: {safe_text(error.get('message') or error)}"
                    )
                result = message.get("result")
                return result if isinstance(result, dict) else {}
        except Exception:
            self._connections.pop(websocket_url, None)
            try:
                connection.close()
            except Exception:
                pass
            raise


def evaluate_expression(
    client: CDPClient,
    target_id: str,
    expression: str,
    *,
    await_promise: bool = True,
    return_by_value: bool = True,
) -> Any:
    target = client.target(target_id)
    result = client.call(
        target.websocket_url,
        "Runtime.evaluate",
        {
            "expression": expression,
            "awaitPromise": await_promise,
            "returnByValue": return_by_value,
            "userGesture": True,
        },
    )
    details = result.get("exceptionDetails")
    if details:
        raise RuntimeError(safe_text(details.get("text") or "JavaScript exception"))
    value = result.get("result", {})
    if "value" in value:
        return value["value"]
    if "description" in value:
        return value["description"]
    return None


def resolve_target(client: CDPClient, args: argparse.Namespace) -> tuple[str, Target]:
    target_id = resolve_target_id(getattr(args, "target_id", None), getattr(args, "task_id", None))
    return target_id, client.target(target_id)


def collect_page_state(client: CDPClient, target_id: str) -> dict[str, Any]:
    page = evaluate_expression(
        client,
        target_id,
        f"""
        (() => {{
          const frames = Array.from(document.querySelectorAll("iframe")).slice(0, 20).map((frame) => ({{
            src: frame.getAttribute("src") || "",
            title: frame.getAttribute("title") || "",
            name: frame.getAttribute("name") || ""
          }}));
          return {{
            title: document.title || "",
            url: window.location.href,
            ready_state: document.readyState,
            body_text: (document.body?.innerText || "").slice(0, {_MAX_TEXT_SNIPPET}),
            frames,
          }};
        }})()
        """,
    )
    return page if isinstance(page, dict) else {}


def collect_media_state(client: CDPClient, target_id: str) -> list[dict[str, Any]]:
    media = evaluate_expression(
        client,
        target_id,
        """
        (() => {
          return Array.from(document.querySelectorAll("video, audio")).slice(0, 20).map((node, index) => ({
            index,
            kind: node.tagName.toLowerCase(),
            current_src: node.currentSrc || "",
            src: node.getAttribute("src") || "",
            poster: node.getAttribute("poster") || "",
            paused: Boolean(node.paused),
            muted: Boolean(node.muted),
            controls: Boolean(node.controls),
            autoplay: Boolean(node.autoplay),
            loop: Boolean(node.loop),
            plays_inline: Boolean(node.playsInline),
            current_time: Number.isFinite(node.currentTime) ? node.currentTime : null,
            duration: Number.isFinite(node.duration) ? node.duration : null,
            ready_state: Number(node.readyState || 0),
          }));
        })()
        """,
    )
    return media if isinstance(media, list) else []


def load_previous_page(token: str) -> dict[str, Any]:
    candidate = Path(token)
    if candidate.is_absolute() or "/" in token:
        payload = json.loads(resolve_local_path(candidate).read_text(encoding="utf-8"))
    else:
        payload = json.loads(
            (browser_bucket("browser-checkpoints") / f"{safe_slug(token, 'checkpoint')}.json").read_text(encoding="utf-8")
        )
    if not isinstance(payload, dict):
        raise ValueError(f"invalid previous challenge payload: {token}")
    page = payload.get("page")
    if isinstance(page, dict):
        return page
    nested = payload.get("challenge")
    if isinstance(nested, dict) and isinstance(nested.get("page"), dict):
        return nested["page"]
    raise ValueError(f"previous challenge payload has no page state: {token}")


def page_signature(page: dict[str, Any]) -> dict[str, Any]:
    return {
        "title": str(page.get("title") or ""),
        "url": str(page.get("url") or ""),
        "ready_state": str(page.get("ready_state") or ""),
        "body_text": str(page.get("body_text") or "")[:512],
        "frames": [
            {
                "src": str(item.get("src") or ""),
                "title": str(item.get("title") or ""),
                "name": str(item.get("name") or ""),
            }
            for item in page.get("frames", [])
            if isinstance(item, dict)
        ],
    }


def challenge_progress(previous_page: dict[str, Any], current_page: dict[str, Any]) -> dict[str, Any]:
    previous = build_challenge_summary(previous_page)
    current = build_challenge_summary(current_page)
    previous_signals = set(previous["signals"])
    current_signals = set(current["signals"])
    signature_changed = page_signature(previous_page) != page_signature(current_page)
    signals_cleared = sorted(previous_signals - current_signals)
    signals_added = sorted(current_signals - previous_signals)
    possible_progress = signature_changed or bool(signals_cleared) or (
        previous["challenge_detected"] and not current["challenge_detected"]
    )
    notes: list[str] = []
    if previous["challenge_detected"] and not current["challenge_detected"]:
        notes.append("Challenge markers dropped, but verify with a fresh snapshot before assuming recovery.")
    if signals_cleared:
        notes.append(f"Signals cleared: {', '.join(signals_cleared)}.")
    if signals_added:
        notes.append(f"Signals added: {', '.join(signals_added)}.")
    if signature_changed and not notes:
        notes.append("The page state changed since the prior check; treat that as possible progress, not proof.")
    if not notes:
        notes.append("No concrete progress markers detected since the prior check.")
    return {
        "previous": previous,
        "signature_changed": signature_changed,
        "signals_cleared": signals_cleared,
        "signals_added": signals_added,
        "possible_progress": possible_progress,
        "notes": notes,
    }


def build_challenge_summary(page: dict[str, Any]) -> dict[str, Any]:
    title = str(page.get("title") or "")
    url = str(page.get("url") or "")
    body_text = str(page.get("body_text") or "")
    frames = page.get("frames") or []
    combined = "\n".join(
        [
            title,
            url,
            body_text,
            *(str(item.get("src") or "") for item in frames if isinstance(item, dict)),
            *(str(item.get("title") or "") for item in frames if isinstance(item, dict)),
        ]
    )
    signals: list[str] = []
    for label, pattern in _CHALLENGE_PATTERNS:
        if pattern.search(combined):
            signals.append(label)
    frame_signals = [
        item for item in frames
        if isinstance(item, dict)
        and any(
            token in str(item.get("src") or "").lower()
            or token in str(item.get("title") or "").lower()
            for token in ["captcha", "recaptcha", "hcaptcha", "turnstile", "challenge"]
        )
    ]
    challenge_detected = bool(signals or frame_signals)
    confidence = "high" if len(signals) >= 2 or frame_signals else "low"
    if challenge_detected and any(signal in signals for signal in ["captcha", "robot_check"]):
        confidence = "medium" if confidence == "low" else confidence
    actions = []
    if not challenge_detected:
        actions.append("No challenge markers detected from the current page state.")
    else:
        actions.append("Refresh the Hermes browser snapshot before every interaction.")
        if "checking_browser" in signals:
            actions.append("Wait 5-10 seconds for the interstitial to complete before clicking.")
        if any(signal in signals for signal in ["captcha", "robot_check", "verification"]):
            actions.append("Use semantic refs first; fall back to browser_vision plus coordinate input only when needed.")
        if frame_signals:
            actions.append("Treat cross-origin challenge frames as stateful; keep the latest frame_id or target_id current.")
        actions.append("Do not claim the challenge is solved until the original page resumes and a fresh snapshot confirms it.")
    return {
        "challenge_detected": challenge_detected,
        "confidence": confidence if challenge_detected else "none",
        "signals": signals,
        "challenge_frames": frame_signals,
        "recommended_actions": actions,
    }


def _body_fragments(page: dict[str, Any], limit: int = 3) -> list[str]:
    fragments: list[str] = []
    for raw_line in str(page.get("body_text") or "").splitlines():
        line = " ".join(raw_line.split()).strip()
        if len(line) < 24:
            continue
        if line not in fragments:
            fragments.append(line[:160])
        if len(fragments) >= limit:
            break
    return fragments


def verify_page_state(
    current_page: dict[str, Any],
    *,
    expected_page: dict[str, Any] | None = None,
    url_substring: str | None = None,
    title_substring: str | None = None,
    body_substrings: list[str] | None = None,
    forbidden_signals: list[str] | None = None,
) -> dict[str, Any]:
    current_challenge = build_challenge_summary(current_page)
    checks: list[dict[str, Any]] = []
    evidence: list[str] = []
    warnings: list[str] = []

    current_url = str(current_page.get("url") or "")
    current_title = str(current_page.get("title") or "")
    current_body = str(current_page.get("body_text") or "")

    def record(name: str, matched: bool, detail: str) -> None:
        checks.append({"name": name, "matched": matched, "detail": detail})
        if matched:
            evidence.append(detail)

    if expected_page is not None:
        expected_url = str(expected_page.get("url") or "")
        expected_title = str(expected_page.get("title") or "")
        expected_path = urlparse(expected_url).path or "/"
        current_path = urlparse(current_url).path or "/"
        expected_fragments = _body_fragments(expected_page)

        if expected_title:
            matched = current_title == expected_title
            record(
                "checkpoint_title",
                matched,
                f"title {'matches' if matched else 'differs from'} checkpoint ({expected_title})",
            )
        if expected_url:
            matched = current_url == expected_url
            record(
                "checkpoint_url",
                matched,
                f"url {'matches' if matched else 'differs from'} checkpoint ({expected_url})",
            )
            path_matched = current_path == expected_path
            record(
                "checkpoint_url_path",
                path_matched,
                f"url path {'matches' if path_matched else 'differs from'} checkpoint ({expected_path})",
            )
        if expected_fragments:
            fragment_hits = [fragment for fragment in expected_fragments if fragment in current_body]
            matched = bool(fragment_hits)
            record(
                "checkpoint_body_fragments",
                matched,
                "body still contains checkpoint text fragments"
                if matched
                else "body no longer contains sampled checkpoint text fragments",
            )

    if url_substring:
        matched = url_substring in current_url
        record(
            "url_substring",
            matched,
            f"url {'contains' if matched else 'does not contain'} {url_substring!r}",
        )
    if title_substring:
        matched = title_substring in current_title
        record(
            "title_substring",
            matched,
            f"title {'contains' if matched else 'does not contain'} {title_substring!r}",
        )
    for token in body_substrings or []:
        matched = token in current_body
        record(
            "body_substring",
            matched,
            f"body {'contains' if matched else 'does not contain'} {token!r}",
        )

    present_signals = set(current_challenge["signals"])
    if forbidden_signals:
        for signal in forbidden_signals:
            matched = signal not in present_signals
            checks.append(
                {
                    "name": "forbidden_signal",
                    "matched": matched,
                    "detail": f"signal {signal!r} {'is absent' if matched else 'is still present'}",
                    "signal": signal,
                }
            )
            if matched:
                evidence.append(f"signal {signal!r} is absent")

    if current_challenge["challenge_detected"]:
        warnings.append(
            "Challenge markers are still present. Treat any page match as provisional until a fresh browser snapshot confirms recovery."
        )

    explicit_failures = [item for item in checks if not item["matched"]]
    explicit_successes = [item for item in checks if item["matched"]]
    matched = bool(checks) and not explicit_failures
    if expected_page is not None and not checks:
        matched = False
        warnings.append("No verification evidence was derived from the checkpoint payload.")
    elif expected_page is not None and checks and not explicit_successes:
        warnings.append("The checkpoint comparison found no positive recovery markers.")
    elif expected_page is not None and explicit_successes and explicit_failures:
        warnings.append("Some checkpoint markers still match, but the page has drifted; verify before resuming.")

    confidence = "high" if matched and not warnings else "medium" if explicit_successes else "low"
    if current_challenge["challenge_detected"]:
        confidence = "low"

    return {
        "matched": matched,
        "confidence": confidence,
        "checks": checks,
        "evidence": evidence,
        "warnings": warnings,
        "challenge": current_challenge,
    }


def profile_backup_path(name: str | None) -> Path:
    slug = safe_slug(name or datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ"), "profile")
    return browser_bucket("browser-profile-backups") / f"{slug}.tar.gz"


def cleanup_cutoff(hours: float) -> float:
    if hours < 0:
        raise ValueError("older-than-hours must be non-negative")
    return time.time() - (hours * 3600)


def handle_targets(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    task_filter = str(args.task_id or "").strip() or None
    targets = [
        {
            "target_id": target.target_id,
            "title": target.title,
            "url": target.url,
            "type": target.type,
            "task_owners": resolve_session_hint(target.target_id),
        }
        for target in client.targets()
    ]
    if task_filter:
        targets = [target for target in targets if task_filter in target["task_owners"]]
    return {"targets": targets}


def handle_session_state(args: argparse.Namespace) -> dict[str, Any]:
    if args.task_id:
        return {"session": load_session_state(args.task_id)}
    return {"sessions": list_session_states()}


def handle_session_events(args: argparse.Namespace) -> dict[str, Any]:
    if args.task_id:
        return {"task_id": args.task_id, "events": load_session_events(args.task_id, args.limit)}
    return {"events": list_session_events(args.limit)}


def handle_frame_tree(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    return {
        "target_id": target_id,
        "frame_tree": client.call(target.websocket_url, "Page.getFrameTree"),
    }


def handle_clipboard_get(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id = resolve_target_id(args.target_id, args.task_id)
    value = evaluate_expression(
        client,
        target_id,
        """
        (async () => {
          if (!navigator.clipboard?.readText) {
            return {available: false, value: null};
          }
          try {
            return {available: true, value: await navigator.clipboard.readText()};
          } catch (error) {
            return {available: true, error: String(error)};
          }
        })()
        """,
    )
    return {"target_id": target_id, "clipboard": value}


def handle_clipboard_set(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id = resolve_target_id(args.target_id, args.task_id)
    payload = json.dumps(args.text)
    value = evaluate_expression(
        client,
        target_id,
        f"""
        (async () => {{
          if (!navigator.clipboard?.writeText) {{
            return {{available: false}};
          }}
          try {{
            await navigator.clipboard.writeText({payload});
            return {{available: true, wrote: true}};
          }} catch (error) {{
            return {{available: true, wrote: false, error: String(error)}};
          }}
        }})()
        """,
    )
    return {"target_id": target_id, "clipboard": value}


def handle_click(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    x = int(args.x)
    y = int(args.y)
    button_mask = _MOUSE_BUTTON_MASKS[args.button]
    client.call(target.websocket_url, "Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
    client.call(
        target.websocket_url,
        "Input.dispatchMouseEvent",
        {
            "type": "mousePressed",
            "x": x,
            "y": y,
            "button": args.button,
            "buttons": button_mask,
            "clickCount": args.click_count,
        },
    )
    try:
        return {
            "target_id": target_id,
            "click": {
                "x": x,
                "y": y,
                "button": args.button,
                "click_count": args.click_count,
            },
        }
    finally:
        client.call(
            target.websocket_url,
            "Input.dispatchMouseEvent",
            {
                "type": "mouseReleased",
                "x": x,
                "y": y,
                "button": args.button,
                "buttons": 0,
                "clickCount": args.click_count,
            },
        )


def handle_touch_tap(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    point = {"x": int(args.x), "y": int(args.y), "radiusX": 1, "radiusY": 1, "force": 1, "id": 1}
    client.call(target.websocket_url, "Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [point]})
    try:
        return {"target_id": target_id, "tap": {"x": int(args.x), "y": int(args.y)}}
    finally:
        client.call(target.websocket_url, "Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})


def handle_touch_swipe(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    steps = max(1, int(args.steps))
    duration_ms = max(0, int(args.duration_ms))
    step_delay = duration_ms / steps / 1000
    start = {"x": int(args.x1), "y": int(args.y1), "radiusX": 1, "radiusY": 1, "force": 1, "id": 1}
    client.call(target.websocket_url, "Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [start]})
    try:
        for step in range(1, steps + 1):
            x = int(args.x1 + ((args.x2 - args.x1) * step / steps))
            y = int(args.y1 + ((args.y2 - args.y1) * step / steps))
            point = {"x": x, "y": y, "radiusX": 1, "radiusY": 1, "force": 1, "id": 1}
            client.call(target.websocket_url, "Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [point]})
            if step_delay:
                time.sleep(step_delay)
    finally:
        client.call(target.websocket_url, "Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    return {
        "target_id": target_id,
        "swipe": {
            "from": [int(args.x1), int(args.y1)],
            "to": [int(args.x2), int(args.y2)],
            "steps": steps,
            "duration_ms": duration_ms,
        },
    }


def handle_drag(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    steps = max(1, int(args.steps))
    duration_ms = max(0, int(args.duration_ms))
    step_delay = duration_ms / steps / 1000
    client.call(target.websocket_url, "Input.dispatchMouseEvent", {"type": "mouseMoved", "x": int(args.x1), "y": int(args.y1)})
    client.call(
        target.websocket_url,
        "Input.dispatchMouseEvent",
        {"type": "mousePressed", "x": int(args.x1), "y": int(args.y1), "button": "left", "buttons": 1, "clickCount": 1},
    )
    current_x = int(args.x1)
    current_y = int(args.y1)
    try:
        for step in range(1, steps + 1):
            current_x = int(args.x1 + ((args.x2 - args.x1) * step / steps))
            current_y = int(args.y1 + ((args.y2 - args.y1) * step / steps))
            client.call(
                target.websocket_url,
                "Input.dispatchMouseEvent",
                {"type": "mouseMoved", "x": current_x, "y": current_y, "button": "left", "buttons": 1},
            )
            if step_delay:
                time.sleep(step_delay)
    finally:
        client.call(
            target.websocket_url,
            "Input.dispatchMouseEvent",
            {"type": "mouseReleased", "x": current_x, "y": current_y, "button": "left", "buttons": 0, "clickCount": 1},
        )
    return {
        "target_id": target_id,
        "drag": {
            "from": [int(args.x1), int(args.y1)],
            "to": [int(args.x2), int(args.y2)],
            "steps": steps,
            "duration_ms": duration_ms,
        },
    }


def handle_media_state(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id = resolve_target_id(args.target_id, args.task_id)
    return {"target_id": target_id, "media": collect_media_state(client, target_id)}


def handle_record_page(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    destination = resolve_output_path(args.path, "browser-recordings", ".webm")
    fps = max(1, int(args.fps))
    interval = 1.0 / fps
    frame_total = max(1, int(round(float(args.seconds) * fps)))
    with tempfile.TemporaryDirectory(prefix="browser-record-", dir=browser_bucket("browser-recordings")) as tempdir:
        frames_dir = Path(tempdir)
        start = time.monotonic()
        for index in range(frame_total):
            screenshot = client.call(target.websocket_url, "Page.captureScreenshot", {"format": "png"})
            screenshot_data = str(screenshot.get("data") or "")
            if not screenshot_data:
                raise RuntimeError("Page.captureScreenshot returned no image data during recording")
            (frames_dir / f"frame-{index:05d}.png").write_bytes(base64.b64decode(screenshot_data))
            if index + 1 < frame_total:
                target_time = start + ((index + 1) * interval)
                delay = target_time - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-framerate",
                str(fps),
                "-i",
                str(frames_dir / "frame-%05d.png"),
                "-c:v",
                "libvpx-vp9",
                "-pix_fmt",
                "yuv420p",
                str(destination),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=max(60, int(args.seconds * 4) + 30),
        )
    return {
        "target_id": target_id,
        "path": str(destination),
        "size_bytes": destination.stat().st_size,
        "fps": fps,
        "seconds": args.seconds,
        "frames": frame_total,
    }


def handle_challenge_state(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id = resolve_target_id(args.target_id, args.task_id)
    page = collect_page_state(client, target_id)
    summary = build_challenge_summary(page)
    progress = None
    if args.previous:
        progress = challenge_progress(load_previous_page(args.previous), page)
    return {"target_id": target_id, "page": page, "challenge": summary, "progress": progress}


def handle_verify_page(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id = resolve_target_id(args.target_id, args.task_id)
    page = collect_page_state(client, target_id)
    expected = load_previous_page(args.expected) if args.expected else None
    verification = verify_page_state(
        page,
        expected_page=expected,
        url_substring=args.url_substring,
        title_substring=args.title_substring,
        body_substrings=args.body_substring or [],
        forbidden_signals=args.without_signal or [],
    )
    return {
        "target_id": target_id,
        "page": page,
        "verification": verification,
        "expected_page": expected,
    }


def handle_checkpoint_save(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    target_id, target = resolve_target(client, args)
    name = safe_slug(args.name, "checkpoint")
    checkpoint_dir = browser_bucket("browser-checkpoints")
    base = checkpoint_dir / name
    screenshot_path = base.with_suffix(".png")
    metadata_path = base.with_suffix(".json")
    screenshot = client.call(target.websocket_url, "Page.captureScreenshot", {"format": "png"})
    screenshot_data = str(screenshot.get("data") or "")
    if not screenshot_data:
        raise RuntimeError("Page.captureScreenshot returned no image data")
    screenshot_path.write_bytes(base64.b64decode(screenshot_data))
    page = collect_page_state(client, target_id)
    record = {
        "name": name,
        "saved_at": iso_now(),
        "target_id": target_id,
        "task_id": getattr(args, "task_id", None) or None,
        "note": args.note or None,
        "page": page,
        "challenge": build_challenge_summary(page),
        "media": collect_media_state(client, target_id),
        "screenshot": str(screenshot_path),
    }
    metadata_path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"checkpoint": record, "metadata_path": str(metadata_path)}


def handle_checkpoint_list(_: argparse.Namespace) -> dict[str, Any]:
    entries = []
    for metadata in sorted(browser_bucket("browser-checkpoints").glob("*.json")):
        try:
            payload = json.loads(metadata.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        entries.append(payload)
    return {"checkpoints": entries}


def handle_checkpoint_delete(args: argparse.Namespace) -> dict[str, Any]:
    name = safe_slug(args.name, "checkpoint")
    removed = []
    for suffix in [".json", ".png"]:
        candidate = browser_bucket("browser-checkpoints") / f"{name}{suffix}"
        if candidate.exists():
            candidate.unlink()
            removed.append(str(candidate))
    return {"name": name, "removed": removed}


def handle_profile_backup(args: argparse.Namespace) -> dict[str, Any]:
    profile = browser_profile_root() / "profile"
    if not profile.is_dir():
        raise ValueError(f"browser profile directory is missing: {profile}")
    destination = profile_backup_path(args.name)
    with tarfile.open(destination, "w:gz") as archive:
        archive.add(profile, arcname="profile")
    return {"path": str(destination), "size_bytes": destination.stat().st_size}


def handle_cleanup(args: argparse.Namespace) -> dict[str, Any]:
    buckets = (
        [
            "browser-checkpoints",
            "browser-profile-backups",
            "browser-session-events",
            "browser-sessions",
            "browser-task-artifacts",
        ]
        if args.bucket == "all"
        else [args.bucket]
    )
    cutoff = cleanup_cutoff(args.older_than_hours)
    removed: list[str] = []
    for bucket in buckets:
        roots = (
            [browser_bucket(bucket)]
            if bucket != "browser-task-artifacts"
            else [
                path
                for path in browser_files_root().iterdir()
                if path.is_dir()
                and path.name
                not in {
                    "android",
                    "android-viewer",
                    "browser-checkpoints",
                    "browser-profile-backups",
                    "browser-session-events",
                    "browser-sessions",
                    "browser-supervisor",
                }
            ]
        )
        for root in roots:
            for candidate in root.rglob("*"):
                try:
                    if candidate.is_file() and candidate.stat().st_mtime < cutoff:
                        candidate.unlink()
                        removed.append(str(candidate))
                except FileNotFoundError:
                    continue
            for directory in sorted(root.rglob("*"), reverse=True):
                try:
                    if directory.is_dir() and not any(directory.iterdir()):
                        directory.rmdir()
                except OSError:
                    continue
    return {"bucket": args.bucket, "removed": removed}


def handle_live_view(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "viewer_url": browser_view_url(),
        "interactive": True,
        "persistent_profile": str(browser_profile_root() / "profile"),
        "supervisor": load_json_file(browser_supervisor_root() / "status.json"),
    }


def handle_diagnostics(args: argparse.Namespace) -> dict[str, Any]:
    client = CDPClient(args.cdp_url)
    version = client.version()
    targets = client.targets()
    profile_root = browser_profile_root()
    policy_root = browser_policy_root()
    unpacked_extensions = profile_root / "extensions-unpacked"
    browser_files = browser_files_root()
    sessions = list_session_states()
    supervisor = load_json_file(browser_supervisor_root() / "status.json")
    android_viewer = load_json_file(browser_files / "android-viewer" / "status.json")
    extension_probes = probe_expected_extensions(
        client, str(version.get("webSocketDebuggerUrl") or "")
    )
    installed_extensions = installed_profile_extensions(profile_root)
    return {
        "cdp": {
            "browser": version.get("Browser"),
            "protocol_version": version.get("Protocol-Version"),
            "user_agent": version.get("User-Agent"),
            "web_socket_debugger_url": version.get("webSocketDebuggerUrl"),
            "target_count": len(targets),
        },
        "sessions": {
            "count": len(sessions),
            "items": sessions,
        },
        "session_events": {
            "count": len(list(event_bucket().glob("*.jsonl"))),
            "recent": list_session_events(20),
        },
        "supervisor": supervisor,
        "android_viewer": android_viewer,
        "extensions": {
            "all_expected_loaded": bool(extension_probes)
            and all(item.get("healthy") for item in extension_probes),
            "expected": extension_probes,
        },
        "profile": {
            "root": str(profile_root),
            "profile_dir": str(profile_root / "profile"),
            "size_bytes": directory_size(profile_root / "profile"),
            "policy_root": str(policy_root),
            "policy_files": [str(path) for path in sorted(policy_root.glob("*.json"))],
            "installed_extensions": installed_extensions,
            "unpacked_extensions": [
                str(path) for path in sorted(unpacked_extensions.iterdir())
            ] if unpacked_extensions.is_dir() else [],
        },
        "browser_files": {
            "root": str(browser_files),
            "size_bytes": directory_size(browser_files),
            "checkpoints": len(list(browser_bucket("browser-checkpoints").glob("*.json"))),
            "profile_backups": len(list(browser_bucket("browser-profile-backups").glob("*.tar.gz"))),
            "task_directories": [
                str(path)
                for path in sorted(browser_files.iterdir())
                if path.is_dir()
                and path.name
                not in {
                    "android",
                    "android-viewer",
                    "browser-checkpoints",
                    "browser-profile-backups",
                    "browser-session-events",
                    "browser-sessions",
                    "browser-supervisor",
                }
            ],
        },
    }


HANDLERS = {
    "targets": handle_targets,
    "session-state": handle_session_state,
    "session-events": handle_session_events,
    "frame-tree": handle_frame_tree,
    "clipboard-get": handle_clipboard_get,
    "clipboard-set": handle_clipboard_set,
    "click": handle_click,
    "touch-tap": handle_touch_tap,
    "touch-swipe": handle_touch_swipe,
    "drag": handle_drag,
    "media-state": handle_media_state,
    "record-page": handle_record_page,
    "challenge-state": handle_challenge_state,
    "verify-page": handle_verify_page,
    "checkpoint-save": handle_checkpoint_save,
    "checkpoint-list": handle_checkpoint_list,
    "checkpoint-delete": handle_checkpoint_delete,
    "profile-backup": handle_profile_backup,
    "cleanup": handle_cleanup,
    "live-view": handle_live_view,
    "diagnostics": handle_diagnostics,
}


def add_target_locator_arguments(command: argparse.ArgumentParser, *, positional: bool = True) -> None:
    if positional:
        command.add_argument("target_id", nargs="?", help="explicit page target ID; defaults to the active target for --task-id")
    else:
        command.add_argument("--target-id", help="explicit page target ID; defaults to the active target for --task-id")
    command.add_argument("--task-id", help="resolve the active target from persisted task-owned browser session metadata")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="browser-support",
        description="Operate the self-hosted Hermes Chromium sidecar through CDP helpers.",
    )
    root.add_argument("--cdp-url", default=default_cdp_url(), help="CDP discovery URL, defaults to BROWSER_CDP_URL")
    sub = root.add_subparsers(dest="command", required=True)

    targets = sub.add_parser("targets", help="list current page targets and their target IDs")
    targets.add_argument("--task-id", help="filter targets to one persisted task session owner")

    session_state = sub.add_parser("session-state", help="show persisted task-owned browser session metadata")
    session_state.add_argument("task_id", nargs="?", help="optional task identifier; omit to list all persisted sessions")

    session_events = sub.add_parser("session-events", help="show persisted task event routing history")
    session_events.add_argument("task_id", nargs="?", help="optional task identifier; omit to merge recent events across tasks")
    session_events.add_argument("--limit", type=int, default=50)

    frame_tree = sub.add_parser("frame-tree", help="return the Page.getFrameTree payload for one target")
    add_target_locator_arguments(frame_tree)

    clipboard_get = sub.add_parser("clipboard-get", help="read navigator.clipboard text from one page target")
    add_target_locator_arguments(clipboard_get)

    clipboard_set = sub.add_parser("clipboard-set", help="write navigator.clipboard text into one page target")
    add_target_locator_arguments(clipboard_set)
    clipboard_set.add_argument("text")

    click = sub.add_parser("click", help="dispatch one atomic mouse click")
    add_target_locator_arguments(click, positional=False)
    click.add_argument("x", type=int)
    click.add_argument("y", type=int)
    click.add_argument("--button", choices=["left", "middle", "right"], default="left")
    click.add_argument("--click-count", type=int, default=1)

    touch_tap = sub.add_parser("touch-tap", help="dispatch one atomic touch tap")
    add_target_locator_arguments(touch_tap, positional=False)
    touch_tap.add_argument("x", type=int)
    touch_tap.add_argument("y", type=int)

    touch_swipe = sub.add_parser("touch-swipe", help="dispatch one touch swipe with interpolated moves")
    add_target_locator_arguments(touch_swipe, positional=False)
    touch_swipe.add_argument("x1", type=int)
    touch_swipe.add_argument("y1", type=int)
    touch_swipe.add_argument("x2", type=int)
    touch_swipe.add_argument("y2", type=int)
    touch_swipe.add_argument("--steps", type=int, default=8)
    touch_swipe.add_argument("--duration-ms", type=int, default=600)

    drag = sub.add_parser("drag", help="dispatch one left-button drag gesture")
    add_target_locator_arguments(drag, positional=False)
    drag.add_argument("x1", type=int)
    drag.add_argument("y1", type=int)
    drag.add_argument("x2", type=int)
    drag.add_argument("y2", type=int)
    drag.add_argument("--steps", type=int, default=12)
    drag.add_argument("--duration-ms", type=int, default=800)

    media_state = sub.add_parser("media-state", help="inspect current audio/video elements in one page target")
    add_target_locator_arguments(media_state)

    record_page = sub.add_parser("record-page", help="capture a viewport recording for one page target")
    add_target_locator_arguments(record_page)
    record_page.add_argument("--seconds", type=float, default=5.0)
    record_page.add_argument("--fps", type=int, default=2)
    record_page.add_argument("path", nargs="?", help="optional process-visible output path")

    challenge = sub.add_parser("challenge-state", help="inspect one page for challenge or verification markers")
    add_target_locator_arguments(challenge)
    challenge.add_argument("--previous", help="previous checkpoint name or JSON path for progress-aware comparison")

    verify_page = sub.add_parser(
        "verify-page",
        help="compare the current page against a checkpoint or explicit recovery markers",
    )
    add_target_locator_arguments(verify_page)
    verify_page.add_argument("--expected", help="checkpoint name or JSON path to compare against")
    verify_page.add_argument("--url-substring", help="require the current URL to contain this substring")
    verify_page.add_argument("--title-substring", help="require the current title to contain this substring")
    verify_page.add_argument(
        "--body-substring",
        action="append",
        help="require the current body text to contain this substring; may be repeated",
    )
    verify_page.add_argument(
        "--without-signal",
        action="append",
        choices=[label for label, _ in _CHALLENGE_PATTERNS],
        help="require one challenge signal to be absent; may be repeated",
    )

    checkpoint_save = sub.add_parser("checkpoint-save", help="save a screenshot-backed checkpoint for one browser page")
    add_target_locator_arguments(checkpoint_save)
    checkpoint_save.add_argument("name")
    checkpoint_save.add_argument("--note")

    sub.add_parser("checkpoint-list", help="list saved browser checkpoints")
    checkpoint_delete = sub.add_parser("checkpoint-delete", help="delete one saved browser checkpoint")
    checkpoint_delete.add_argument("name")

    profile_backup = sub.add_parser("profile-backup", help="archive the persistent Chromium profile to browser files")
    profile_backup.add_argument("name", nargs="?")

    cleanup = sub.add_parser("cleanup", help="remove older browser artifacts from shared storage")
    cleanup.add_argument(
        "bucket",
        choices=[
            "browser-checkpoints",
            "browser-profile-backups",
            "browser-session-events",
            "browser-sessions",
            "browser-task-artifacts",
            "all",
        ],
    )
    cleanup.add_argument("--older-than-hours", type=float, default=168.0)

    sub.add_parser("live-view", help="show the authenticated interactive Chromium console URL")
    sub.add_parser("diagnostics", help="report CDP, profile, policy, extension, and storage details")
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        result = HANDLERS[args.command](args)
    except (ValueError, RuntimeError, requests.RequestException, OSError, tarfile.TarError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"browser-support: {safe_text(exc)}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(
            f"browser-support: request failed: {type(exc).__name__}: {safe_text(exc)}",
            file=sys.stderr,
        )
        return 1
    compact({"ok": True, **result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
