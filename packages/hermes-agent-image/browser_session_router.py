"""Task-scoped tab groups for a shared persistent Chrome profile."""

from __future__ import annotations

import json
import os
import re
import shutil
import threading
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional


_ROUTER_LOCK = threading.RLock()
_SESSION_LOCKS: Dict[str, threading.RLock] = {}
_INFLIGHT_COMMANDS: Dict[str, Dict[str, Any]] = {}
_POPUP_SETTLE_COMMANDS = {"click", "mouse", "press"}


def enabled() -> bool:
    return os.environ.get("BROWSER_SHARED_PROFILE_SESSIONS", "").lower() in {
        "1", "true", "yes", "on",
    }


def _cdp(cdp_url: str, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    from tools.browser_cdp_tool import _cdp_call, _run_async

    return _run_async(_cdp_call(cdp_url, method, params or {}, None, 10.0))


def create_target_group(cdp_url: str) -> Dict[str, Any]:
    """Create a root page in Chrome's default context for a new Hermes task."""
    if not enabled():
        return {}
    with _ROUTER_LOCK:
        created = _cdp(cdp_url, "Target.createTarget", {"url": "about:blank"})
        target_id = str(created.get("targetId") or "")
        if not target_id:
            raise RuntimeError("Chrome did not return a target ID for the browser session")
        return {
            "shared_profile_session": True,
            "root_target_id": target_id,
            "active_target_id": target_id,
            "owned_target_ids": [target_id],
        }


def _page_targets(cdp_url: str) -> Dict[str, Dict[str, Any]]:
    response = _cdp(cdp_url, "Target.getTargets")
    return {
        str(info["targetId"]): info
        for info in response.get("targetInfos", [])
        if info.get("type") == "page" and info.get("targetId")
    }


def _live_owned(session: Dict[str, Any], targets: Dict[str, Dict[str, Any]]) -> List[str]:
    owned = [str(item) for item in session.get("owned_target_ids", [])]
    return [target_id for target_id in owned if target_id in targets]


def _task_lock(task_id: str) -> threading.RLock:
    with _ROUTER_LOCK:
        lock = _SESSION_LOCKS.get(task_id)
        if lock is None:
            lock = threading.RLock()
            _SESSION_LOCKS[task_id] = lock
        return lock


def _event_root() -> Path:
    destination = _files_root() / "browser-session-events"
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def _event_path(task_id: str) -> Path:
    return _event_root() / f"{_safe_task_name(task_id)}.jsonl"


def _append_event(task_id: str, event: str, **payload: Any) -> None:
    if not task_id:
        return
    record = {
        "recorded_at": _now_iso(),
        "task_id": task_id,
        "event": event,
        **payload,
    }
    with _ROUTER_LOCK:
        with _event_path(task_id).open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")


def list_persisted_events(task_id: Optional[str] = None, limit: int = 50) -> List[Dict[str, Any]]:
    candidates = [_event_path(task_id)] if task_id else sorted(_event_root().glob("*.jsonl"))
    events: List[Dict[str, Any]] = []
    for path in candidates:
        if not path.exists():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            continue
        for line in lines[-max(1, limit):]:
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                events.append(payload)
    return events[-max(1, limit):]


def _claim_popup_descendants(
    session: Dict[str, Any], targets: Dict[str, Dict[str, Any]], new_ids: Iterable[str] = (),
) -> tuple[List[str], List[str], List[str]]:
    """Claim opener descendants plus targets created by the serialized command."""
    owned = set(_live_owned(session, targets))
    changed = True
    while changed:
        changed = False
        for target_id, info in targets.items():
            if target_id not in owned and str(info.get("openerId") or "") in owned:
                owned.add(target_id)
                changed = True
    # A target with an opener owned by another task is not ours, even if it
    # happened to appear while this serialized command was running.  Only the
    # opener-less delta is the fallback for rel=noopener/window.open(...).
    claimed_orphans = sorted(
        target_id
        for target_id in new_ids
        if target_id in targets and not targets[target_id].get("openerId")
    )
    owned.update(claimed_orphans)
    ignored_orphans = sorted(
        target_id for target_id in new_ids
        if target_id in targets and target_id not in owned
    )
    ordered = [item for item in session.get("owned_target_ids", []) if item in owned]
    ordered.extend(target_id for target_id in targets if target_id in owned and target_id not in ordered)
    session["owned_target_ids"] = ordered
    return ordered, claimed_orphans, ignored_orphans


def _tabs(result: Dict[str, Any]) -> List[Dict[str, Any]]:
    data = result.get("data", {}) if isinstance(result, dict) else {}
    tabs = data.get("tabs", []) if isinstance(data, dict) else []
    return tabs if isinstance(tabs, list) else []


def _tab_reference(tab: Dict[str, Any]) -> Optional[str]:
    """Return the strongest tab selector supported by the CLI response."""
    for key in ("tabId", "label", "index"):
        value = tab.get(key)
        if value is None:
            continue
        reference = str(value).strip()
        if reference:
            return reference
    return None


def _select_target(
    task_id: str,
    session: Dict[str, Any],
    raw_run: Callable[..., Dict[str, Any]],
    target_id: str,
    timeout: Optional[int],
) -> Optional[Dict[str, Any]]:
    """Switch this task's agent-browser daemon to a Chrome target ID."""
    listed: Dict[str, Any] = {}
    for attempt in range(3):
        listed = raw_run(task_id, "tab", [], timeout=timeout)
        for tab in _tabs(listed):
            if str(tab.get("targetId") or "") == target_id:
                tab_reference = _tab_reference(tab)
                if tab_reference is None:
                    return {
                        "success": False,
                        "error": f"Browser target {target_id} has no selectable tab reference",
                        "details": tab,
                    }
                switched = raw_run(
                    task_id, "tab", [tab_reference], timeout=timeout)
                if switched.get("success"):
                    return None
                return switched
        if attempt < 2:
            time.sleep(0.1)
    return {
        "success": False,
        "error": f"Browser target {target_id} is not attached to this session",
        "details": listed,
    }


def _retarget_supervisor(task_id: str, previous: str, current: str) -> None:
    if not current or current == previous:
        return
    try:
        from tools.browser_supervisor import SUPERVISOR_REGISTRY
        from tools.browser_tool import _ensure_cdp_supervisor

        SUPERVISOR_REGISTRY.stop(task_id)
        _ensure_cdp_supervisor(task_id)
    except Exception:
        pass


def run(
    task_id: str,
    session: Dict[str, Any],
    raw_run: Callable[..., Dict[str, Any]],
    command: str,
    args: List[str],
    timeout: Optional[int],
    engine_override: Optional[str],
) -> Dict[str, Any]:
    """Run one command against the active target owned by this Hermes task."""
    if not session.get("shared_profile_session"):
        return raw_run(task_id, command, args, timeout, engine_override)

    session["task_id"] = task_id
    cdp_url = str(session.get("cdp_url") or "")
    with _task_lock(task_id):
        before = _page_targets(cdp_url)
        owned, _, _ = _claim_popup_descendants(session, before)
        active = str(session.get("active_target_id") or "")
        if active not in owned:
            active = owned[-1] if owned else ""
        if not active:
            created = create_target_group(cdp_url)
            session.update(created)
            active = str(session["active_target_id"])
            persist_session(task_id, session)
            _append_event(
                task_id,
                "session.created",
                active_target_id=active,
                root_target_id=session.get("root_target_id"),
            )

        select_error = _select_target(task_id, session, raw_run, active, timeout)
        if select_error:
            persist_session(task_id, session)
            _append_event(
                task_id,
                "command.select_failed",
                command=command,
                active_target_id=active,
                error=select_error.get("error"),
            )
            return select_error

        command_id = uuid.uuid4().hex[:12]
        with _ROUTER_LOCK:
            _INFLIGHT_COMMANDS[command_id] = {
                "task_id": task_id,
                "command": command,
                "started_at": _now_iso(),
                "active_target_id": active,
            }
        _append_event(
            task_id,
            "command.started",
            command_id=command_id,
            command=command,
            active_target_id=active,
        )
        try:
            result = raw_run(task_id, command, args, timeout, engine_override)
            if command in _POPUP_SETTLE_COMMANDS:
                time.sleep(0.2)
        finally:
            with _ROUTER_LOCK:
                overlapping_tasks = sorted(
                    {
                        str(entry.get("task_id") or "")
                        for key, entry in _INFLIGHT_COMMANDS.items()
                        if key != command_id and str(entry.get("task_id") or "") != task_id
                    }
                )
                _INFLIGHT_COMMANDS.pop(command_id, None)

        after = _page_targets(cdp_url)
        new_ids = set(after) - set(before)
        allow_orphans = len(overlapping_tasks) == 0
        claimed_new_ids = [
            target_id
            for target_id in new_ids
            if target_id in after and str(after[target_id].get("openerId") or "") in owned
        ]
        owned, claimed_orphans, ignored_orphans = _claim_popup_descendants(
            session,
            after,
            new_ids if allow_orphans else claimed_new_ids,
        )
        previous = active
        popup_ids = [target_id for target_id in owned if target_id in new_ids]
        if popup_ids:
            active = popup_ids[-1]
        elif active not in after:
            active = owned[-1] if owned else ""
        session["active_target_id"] = active
        persist_session(task_id, session)
        _retarget_supervisor(task_id, previous, active)
        _append_event(
            task_id,
            "command.completed",
            command_id=command_id,
            command=command,
            active_target_id=active,
            previous_target_id=previous,
            new_target_ids=sorted(str(target_id) for target_id in new_ids),
            popup_target_ids=popup_ids,
            claimed_orphan_target_ids=claimed_orphans,
            ignored_orphan_target_ids=ignored_orphans,
            overlapping_tasks=overlapping_tasks,
            success=bool(result.get("success", True)),
        )
        return result


def close_target_group(session: Dict[str, Any]) -> None:
    """Close only this task's pages, never the shared Chrome process/profile."""
    if not session.get("shared_profile_session"):
        return
    cdp_url = str(session.get("cdp_url") or "")
    with _ROUTER_LOCK:
        try:
            targets = _page_targets(cdp_url)
        except Exception:
            targets = {}
        for target_id in reversed(_live_owned(session, targets)):
            try:
                _cdp(cdp_url, "Target.closeTarget", {"targetId": target_id})
            except Exception:
                pass
        task_id = str(session.get("task_id") or "")
        remove_persisted_session(task_id)
        _append_event(task_id, "session.closed", closed_target_ids=_live_owned(session, targets))


def _files_root() -> Path:
    return Path(os.environ.get("BROWSER_FILES_ROOT", "/opt/browser-files")).resolve()


def _session_root() -> Path:
    destination = _files_root() / "browser-sessions"
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def _safe_task_name(task_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", task_id)[:80] or "default"


def _session_path(task_id: str) -> Path:
    return _session_root() / f"{_safe_task_name(task_id)}.json"


def _now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def persist_session(task_id: str, session: Dict[str, Any]) -> None:
    """Persist one task-owned browser session under shared browser storage."""
    if not task_id or not session.get("shared_profile_session"):
        return
    session["task_id"] = task_id
    payload = {
        "task_id": task_id,
        "updated_at": _now_iso(),
        "shared_profile_session": True,
        "cdp_url": session.get("cdp_url"),
        "root_target_id": session.get("root_target_id"),
        "active_target_id": session.get("active_target_id"),
        "owned_target_ids": [
            str(target_id)
            for target_id in session.get("owned_target_ids", [])
            if str(target_id)
        ],
        "event_log_path": str(_event_path(task_id)),
    }
    destination = _session_path(task_id)
    temp = destination.with_suffix(".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(destination)


def remove_persisted_session(task_id: str) -> None:
    """Remove live-session metadata while retaining its diagnostic event log."""
    if not task_id:
        return
    try:
        _session_path(task_id).unlink()
    except FileNotFoundError:
        pass


def load_persisted_session(task_id: str) -> Dict[str, Any]:
    payload = json.loads(_session_path(task_id).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Invalid browser session metadata for task {task_id}")
    return payload


def list_persisted_sessions() -> List[Dict[str, Any]]:
    sessions: List[Dict[str, Any]] = []
    for path in sorted(_session_root().glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            continue
        if isinstance(payload, dict):
            sessions.append(payload)
    return sessions


def _task_directory(task_id: str, kind: str) -> Path:
    safe_task = _safe_task_name(task_id)
    destination = _files_root() / safe_task / kind
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def stage_uploads(task_id: str, paths: List[str]) -> List[str]:
    """Copy agent-visible files into the path shared with the Chrome sidecar."""
    if not paths:
        raise ValueError("Upload requires at least one file")
    sources: List[Path] = []
    for raw_path in paths:
        source = Path(raw_path).expanduser().resolve(strict=True)
        if not source.is_file():
            raise ValueError(f"Upload source is not a regular file: {raw_path}")
        sources.append(source)

    destination = _task_directory(task_id, "uploads")
    staged: List[str] = []
    for source in sources:
        name = re.sub(r"[^A-Za-z0-9_.-]", "_", source.name) or "upload"
        target = destination / f"{uuid.uuid4().hex[:10]}-{name}"
        shutil.copy2(source, target)
        staged.append(str(target))
    return staged


def download_path(task_id: str, filename: str) -> str:
    """Allocate a collision-free browser download path on shared storage."""
    safe_name = re.sub(r"[^A-Za-z0-9_.-]", "_", Path(filename).name)
    if not safe_name or safe_name in {".", ".."}:
        raise ValueError("filename must contain a valid file name")
    return str(
        _task_directory(task_id, "downloads")
        / f"{uuid.uuid4().hex[:10]}-{safe_name}"
    )
