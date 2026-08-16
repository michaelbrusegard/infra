"""Task-scoped tab groups for a shared persistent Chrome profile."""

from __future__ import annotations

import os
import re
import shutil
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional


_COMMAND_LOCK = threading.RLock()
_MAX_UPLOAD_FILES = 10
_MAX_UPLOAD_FILE_BYTES = 100 * 1024 * 1024
_MAX_UPLOAD_TOTAL_BYTES = 250 * 1024 * 1024
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
    with _COMMAND_LOCK:
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


def _claim_popup_descendants(
    session: Dict[str, Any], targets: Dict[str, Dict[str, Any]], new_ids: Iterable[str] = (),
) -> List[str]:
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
    owned.update(
        target_id
        for target_id in new_ids
        if target_id in targets and not targets[target_id].get("openerId")
    )
    ordered = [item for item in session.get("owned_target_ids", []) if item in owned]
    ordered.extend(target_id for target_id in targets if target_id in owned and target_id not in ordered)
    session["owned_target_ids"] = ordered
    return ordered


def _tabs(result: Dict[str, Any]) -> List[Dict[str, Any]]:
    data = result.get("data", {}) if isinstance(result, dict) else {}
    tabs = data.get("tabs", []) if isinstance(data, dict) else []
    return tabs if isinstance(tabs, list) else []


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
                switched = raw_run(
                    task_id, "tab", [str(tab.get("index"))], timeout=timeout)
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

    cdp_url = str(session.get("cdp_url") or "")
    with _COMMAND_LOCK:
        before = _page_targets(cdp_url)
        owned = _claim_popup_descendants(session, before)
        active = str(session.get("active_target_id") or "")
        if active not in owned:
            active = owned[-1] if owned else ""
        if not active:
            created = create_target_group(cdp_url)
            session.update(created)
            active = str(session["active_target_id"])

        select_error = _select_target(task_id, session, raw_run, active, timeout)
        if select_error:
            return select_error

        result = raw_run(task_id, command, args, timeout, engine_override)
        if command in _POPUP_SETTLE_COMMANDS:
            time.sleep(0.2)

        after = _page_targets(cdp_url)
        new_ids = set(after) - set(before)
        owned = _claim_popup_descendants(session, after, new_ids)
        previous = active
        popup_ids = [target_id for target_id in owned if target_id in new_ids]
        if popup_ids:
            active = popup_ids[-1]
        elif active not in after:
            active = owned[-1] if owned else ""
        session["active_target_id"] = active
        _retarget_supervisor(task_id, previous, active)
        return result


def close_target_group(session: Dict[str, Any]) -> None:
    """Close only this task's pages, never the shared Chrome process/profile."""
    if not session.get("shared_profile_session"):
        return
    cdp_url = str(session.get("cdp_url") or "")
    with _COMMAND_LOCK:
        try:
            targets = _page_targets(cdp_url)
        except Exception:
            targets = {}
        for target_id in reversed(_live_owned(session, targets)):
            try:
                _cdp(cdp_url, "Target.closeTarget", {"targetId": target_id})
            except Exception:
                pass


def _files_root() -> Path:
    return Path(os.environ.get("BROWSER_FILES_ROOT", "/opt/browser-files")).resolve()


def _task_directory(task_id: str, kind: str) -> Path:
    safe_task = re.sub(r"[^A-Za-z0-9_.-]", "_", task_id)[:80] or "default"
    destination = _files_root() / safe_task / kind
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def stage_uploads(task_id: str, paths: List[str]) -> List[str]:
    """Copy agent-visible files into the path shared with the Chrome sidecar."""
    if not paths or len(paths) > _MAX_UPLOAD_FILES:
        raise ValueError(f"Upload requires 1-{_MAX_UPLOAD_FILES} files")
    hermes_home = Path(os.environ.get("HERMES_HOME", "/opt/data"))
    allowed_roots = [
        (hermes_home / "workspace").resolve(),
        (hermes_home / "cache").resolve(),
        _files_root(),
    ]
    sources: List[Path] = []
    total = 0
    for raw_path in paths:
        source = Path(raw_path).expanduser().resolve(strict=True)
        if not source.is_file() or source.is_symlink():
            raise ValueError(f"Upload source is not a regular file: {raw_path}")
        if not any(source.is_relative_to(root) for root in allowed_roots):
            raise ValueError(f"Upload source must be under a Hermes workspace or cache: {raw_path}")
        size = source.stat().st_size
        if size > _MAX_UPLOAD_FILE_BYTES:
            raise ValueError(f"Upload file exceeds 100 MiB: {source.name}")
        total += size
        if total > _MAX_UPLOAD_TOTAL_BYTES:
            raise ValueError("Combined upload size exceeds 250 MiB")
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
