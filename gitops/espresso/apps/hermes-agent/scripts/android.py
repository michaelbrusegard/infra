#!/usr/bin/env python3
"""Android automation and unrestricted adb passthrough for Hermes."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


_SAFE_NAME = re.compile(r"[^A-Za-z0-9_.-]+")
_BOUNDS = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
_SIMPLE_INPUT_TEXT = re.compile(r"^[A-Za-z0-9@%+=:,./_-]+(?: [A-Za-z0-9@%+=:,./_-]+)*$")
_AURORA_STORE_VERSION = "4.8.4"
_AURORA_STORE_PACKAGE = "com.aurora.store"
_AURORA_STORE_SHA256 = "8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad"
_AURORA_STORE_APK = Path(f"/opt/android/apks/AuroraStore-{_AURORA_STORE_VERSION}.apk")
_DEFAULT_REF_TTL_SECONDS = 30.0
_DEFAULT_VERIFY_TIMEOUT_SECONDS = 3.0
_ACCESSIBILITY_GUEST_PORT = 8765
_MAX_ACCESSIBILITY_REQUEST_BYTES = 1024 * 1024
_MAX_ACCESSIBILITY_RESPONSE_BYTES = 32 * 1024 * 1024


def compact(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def safe_text(value: Any) -> str:
    return str(value).strip()[:500]


def safe_device_name(value: str) -> str:
    return _SAFE_NAME.sub("_", value.strip())[:80] or "default"


def env_name(serial: str) -> str:
    return _SAFE_NAME.sub("_", serial.strip()).upper() or "DEFAULT"


def browser_files_root() -> Path:
    return Path(os.environ.get("BROWSER_FILES_ROOT", "/opt/browser-files")).resolve()


def resolve_local_source(raw_path: str) -> Path:
    source = Path(raw_path).expanduser().resolve()
    if not source.is_file():
        raise ValueError(f"local source is not a regular file: {raw_path}")
    return source


def device_directory(serial: str, bucket: str) -> Path:
    destination = browser_files_root() / "android" / safe_device_name(serial) / bucket
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def resolve_output_path(
    raw_path: str | None,
    serial: str,
    bucket: str,
    extension: str,
) -> Path:
    suffix = extension if extension.startswith(".") else f".{extension}"
    if raw_path:
        destination = Path(raw_path).expanduser().resolve()
        if destination.name in {"", ".", ".."}:
            raise ValueError("output path must name a file")
        destination.parent.mkdir(parents=True, exist_ok=True)
        return destination
    return device_directory(serial, bucket) / f"{uuid.uuid4().hex[:12]}{suffix}"


def encode_input_text(value: str) -> str:
    cleaned = re.sub(r"\s+", "%s", value.strip())
    if not cleaned:
        raise ValueError("text must not be empty")
    return cleaned


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("value must be at least 1")
    return parsed


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be greater than 0")
    return parsed


def default_adb_endpoint() -> str | None:
    return os.environ.get("ANDROID_ADB_ENDPOINT") or None


def iso_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso8601(value: str) -> datetime:
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def load_json_file(path: Path) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    return payload if isinstance(payload, dict) else None


def default_grpc_endpoint(serial: str | None = None) -> str | None:
    candidates = []
    if serial:
        suffix = env_name(serial)
        candidates.extend(
            [
                os.environ.get(f"ANDROID_GRPC_URL_{suffix}"),
                os.environ.get(f"ANDROID_EMULATOR_GRPC_URL_{suffix}"),
            ]
        )
    candidates.extend(
        [
            os.environ.get("ANDROID_GRPC_URL"),
            os.environ.get("ANDROID_EMULATOR_GRPC_URL"),
        ]
    )
    for candidate in candidates:
        if candidate:
            return candidate
    return None


def default_view_endpoint(serial: str | None = None) -> str | None:
    candidates = []
    if serial:
        candidates.append(os.environ.get(f"ANDROID_VIEW_URL_{env_name(serial)}"))
    candidates.append(os.environ.get("ANDROID_VIEW_URL"))
    return next((candidate for candidate in candidates if candidate), None)


def default_companion_endpoint(serial: str | None = None) -> str | None:
    del serial
    candidates = [
        os.environ.get("ANDROID_COMPANION_URL"),
        os.environ.get("ANDROID_ACCESSIBILITY_COMPANION_URL"),
    ]
    return next((candidate for candidate in candidates if candidate), None)


def is_tcp_endpoint(serial: str) -> bool:
    value = serial.strip()
    if not value:
        return False
    if re.fullmatch(r"emulator-\d+", value):
        return False
    return ":" in value


def parse_devices(output: str) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("List of devices attached"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        entry: dict[str, Any] = {
            "serial": parts[0],
            "state": parts[1],
        }
        for token in parts[2:]:
            if ":" in token:
                key, value = token.split(":", 1)
                entry[key] = value
        devices.append(entry)
    return devices


def adb_command(serial: str | None, *args: str) -> list[str]:
    command = ["adb"]
    if serial:
        command.extend(["-s", serial])
    command.extend(args)
    return command


def grpc_target(endpoint: str) -> str:
    parsed = urlparse(endpoint)
    if parsed.scheme and parsed.netloc:
        return parsed.netloc
    if parsed.scheme and parsed.path:
        return parsed.path
    return endpoint


def run_adb(
    serial: str | None,
    *args: str,
    check: bool = True,
    text: bool = True,
    timeout: int = 120,
) -> str | bytes:
    completed = subprocess.run(
        adb_command(serial, *args),
        check=False,
        capture_output=True,
        text=text,
        timeout=timeout,
    )
    if check and completed.returncode != 0:
        stderr = completed.stderr if text else completed.stderr.decode("utf-8", "replace")
        raise RuntimeError(f"adb {' '.join(args)} failed: {safe_text(stderr)}")
    return completed.stdout


def run_grpc(
    endpoint: str,
    method: str,
    payload: dict[str, Any] | None = None,
    *,
    timeout: int = 60,
    check: bool = True,
) -> str:
    command = [
        "grpcurl",
        "-plaintext",
        "-emit-defaults",
    ]
    token_file = Path(
        os.environ.get(
            "ANDROID_EMULATOR_GRPC_TOKEN_FILE",
            "/opt/android/companion/emulator-grpc-token",
        )
    )
    try:
        token = token_file.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise RuntimeError(f"unable to read emulator gRPC token: {safe_text(exc)}") from exc
    if not token:
        raise RuntimeError(f"empty emulator gRPC token file: {token_file}")
    proto_file = token_file.parent / "emulator_controller.proto"
    if proto_file.is_file():
        command.extend(
            [
                "-import-path",
                str(proto_file.parent),
                "-proto",
                proto_file.name,
            ]
        )
    command.extend(
        [
            "-H",
            f"authorization: Bearer {token}",
            "-d",
            json.dumps(payload or {}, ensure_ascii=False),
            grpc_target(endpoint),
            method,
        ]
    )
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except OSError as exc:
        raise RuntimeError(f"unable to run grpcurl: {safe_text(exc)}") from exc
    if check and completed.returncode != 0:
        raise RuntimeError(f"{method} failed: {safe_text(completed.stderr)}")
    return completed.stdout.strip()


def chosen_serial(args: argparse.Namespace) -> str | None:
    return args.serial or os.environ.get("ANDROID_SERIAL") or default_adb_endpoint() or None


def require_serial(args: argparse.Namespace) -> str:
    serial = chosen_serial(args)
    if not serial:
        raise ValueError("set --serial or ANDROID_SERIAL when targeting one Android device")
    return serial


def connected_devices() -> list[dict[str, Any]]:
    return parse_devices(str(run_adb(None, "devices", "-l")))


def device_entry(serial: str) -> dict[str, Any] | None:
    for entry in connected_devices():
        if entry.get("serial") == serial:
            return entry
    return None


def ensure_device_connection(serial: str) -> None:
    if not is_tcp_endpoint(serial):
        return
    state = device_entry(serial)
    if state and state.get("state") == "device":
        return
    run_adb(None, "connect", serial, check=False)


def require_connected_serial(args: argparse.Namespace) -> str:
    serial = require_serial(args)
    ensure_device_connection(serial)
    return serial


def default_grpc_url_for_serial(serial: str) -> str:
    grpc_url = default_grpc_endpoint(serial)
    if not grpc_url:
        raise RuntimeError(
            "set ANDROID_EMULATOR_GRPC_URL or ANDROID_GRPC_URL to use emulator gRPC features"
        )
    return grpc_url


def grpc_json(
    serial: str,
    method: str,
    payload: dict[str, Any] | None = None,
    *,
    timeout: int = 60,
) -> dict[str, Any]:
    response = run_grpc(default_grpc_url_for_serial(serial), method, payload, timeout=timeout)
    if not response:
        return {}
    parsed = json.loads(response)
    if not isinstance(parsed, dict):
        raise RuntimeError(f"{method} returned a non-object response")
    return parsed


def accessibility_request(
    serial: str,
    payload: dict[str, Any],
    *,
    timeout: float = 20.0,
) -> dict[str, Any]:
    token_file = Path(
        os.environ.get(
            "ANDROID_COMPANION_TOKEN_FILE",
            "/opt/android/companion/auth-token",
        )
    )
    try:
        token = token_file.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise RuntimeError(f"unable to read accessibility companion token: {safe_text(exc)}") from exc
    if not token:
        raise RuntimeError(f"empty accessibility companion token file: {token_file}")
    authenticated_payload = {**payload, "token": token}
    request = (
        json.dumps(authenticated_payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        + b"\n"
    )
    if len(request) > _MAX_ACCESSIBILITY_REQUEST_BYTES:
        raise RuntimeError("accessibility companion request exceeds one MiB")

    remote_request = f"/data/local/tmp/hermes-accessibility-{uuid.uuid4().hex}.json"
    command_timeout = max(5, int(timeout) + 5)
    with tempfile.NamedTemporaryFile(prefix="hermes-accessibility-", suffix=".json") as request_file:
        request_file.write(request)
        request_file.flush()
        run_adb(serial, "push", request_file.name, remote_request, timeout=command_timeout)
        try:
            raw_response = run_adb(
                serial,
                "shell",
                f"nc -w {max(1, int(timeout))} 127.0.0.1 {_ACCESSIBILITY_GUEST_PORT} < {remote_request}",
                text=False,
                timeout=command_timeout,
            )
        finally:
            run_adb(
                serial,
                "shell",
                "rm",
                "-f",
                remote_request,
                check=False,
                timeout=command_timeout,
            )

    assert isinstance(raw_response, bytes)
    if len(raw_response) > _MAX_ACCESSIBILITY_RESPONSE_BYTES:
        raise RuntimeError("accessibility companion response exceeds 32 MiB")
    raw = raw_response.split(b"\n", 1)[0]
    if not raw:
        raise RuntimeError("accessibility companion returned an empty response")
    try:
        response = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("accessibility companion returned invalid JSON") from exc
    if not isinstance(response, dict):
        raise RuntimeError("accessibility companion returned a non-object response")
    if not response.get("ok"):
        raise RuntimeError(
            f"accessibility companion rejected request: {safe_text(response.get('error', 'unknown error'))}"
        )
    return response


def epoch_ms_iso(value: int | float) -> str:
    return (
        datetime.fromtimestamp(float(value) / 1000.0, UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def accessibility_snapshot(serial: str, ttl_seconds: float | None = None) -> dict[str, Any]:
    ttl = ttl_seconds if ttl_seconds is not None else ref_ttl_seconds()
    response = accessibility_request(
        serial,
        {"op": "snapshot", "ttl_ms": max(1000, int(ttl * 1000))},
    )
    response["serial"] = serial
    response["captured_at"] = epoch_ms_iso(response["captured_at_ms"])
    response["expires_at"] = epoch_ms_iso(response["expires_at_ms"])
    response["ref_ttl_seconds"] = ttl
    return response


def accessibility_action(
    serial: str,
    tree_id: str,
    ref: str,
    action: str,
    *,
    value: str | None = None,
    verify_timeout: float = _DEFAULT_VERIFY_TIMEOUT_SECONDS,
    require_change: bool = False,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "op": "action",
        "tree_id": tree_id,
        "ref": ref,
        "action": action,
        "verify_timeout_ms": max(0, int(verify_timeout * 1000)),
        "require_change": require_change,
        "fallback_gesture": True,
    }
    if value is not None:
        payload["value"] = value
    return accessibility_request(serial, payload, timeout=max(20.0, verify_timeout + 10.0))


def accessibility_gesture(serial: str, gesture: dict[str, Any]) -> dict[str, Any]:
    return accessibility_request(serial, {"op": "gesture", **gesture})


def shell_text(serial: str, *args: str, timeout: int = 120) -> str:
    return str(run_adb(serial, "shell", *args, timeout=timeout)).strip()


def shell_bool(serial: str, *args: str) -> bool:
    return shell_text(serial, *args).lower() in {"1", "true", "yes", "ok"}


def parse_wm_size(output: str) -> dict[str, int] | None:
    match = re.search(r"(\d+)x(\d+)", output)
    if not match:
        return None
    return {"width": int(match.group(1)), "height": int(match.group(2))}


def parse_focus(output: str) -> str | None:
    for line in output.splitlines():
        line = line.strip()
        if "mCurrentFocus" in line or "mFocusedApp" in line:
            return safe_text(line)
    return None


def parse_bounds(value: str) -> dict[str, Any] | None:
    match = _BOUNDS.fullmatch(value)
    if not match:
        return None
    left, top, right, bottom = (int(part) for part in match.groups())
    if right < left or bottom < top:
        return None
    return {
        "left": left,
        "top": top,
        "right": right,
        "bottom": bottom,
        "center": [(left + right) // 2, (top + bottom) // 2],
    }


def parse_ui_tree(xml: str) -> dict[str, Any]:
    root = ET.fromstring(xml)
    nodes: list[dict[str, Any]] = []
    for element in root.iter("node"):
        attributes = element.attrib
        bounds = parse_bounds(attributes.get("bounds", ""))
        if bounds is None:
            continue
        node: dict[str, Any] = {
            "ref": f"r{len(nodes) + 1}",
            "bounds": bounds,
        }
        optional = {
            "text": attributes.get("text"),
            "description": attributes.get("content-desc"),
            "resource_id": attributes.get("resource-id"),
            "class": attributes.get("class"),
            "package": attributes.get("package"),
        }
        node.update({key: value for key, value in optional.items() if value})
        for key in ("clickable", "long-clickable", "scrollable", "focusable", "focused", "enabled"):
            if key in attributes:
                node[key.replace("-", "_")] = attributes[key] == "true"
        nodes.append(node)
    return {
        "tree_id": hashlib.sha256(xml.encode("utf-8")).hexdigest()[:16],
        "nodes": nodes,
    }


def ref_ttl_seconds() -> float:
    raw = os.environ.get("ANDROID_UI_REF_TTL_SECONDS", "")
    if not raw:
        return _DEFAULT_REF_TTL_SECONDS
    try:
        parsed = float(raw)
    except ValueError:
        return _DEFAULT_REF_TTL_SECONDS
    return parsed if parsed > 0 else _DEFAULT_REF_TTL_SECONDS


def stamp_tree(tree: dict[str, Any], ttl_seconds: float | None = None) -> dict[str, Any]:
    ttl = ttl_seconds if ttl_seconds is not None else ref_ttl_seconds()
    captured_at = datetime.now(UTC)
    expires_at = captured_at.timestamp() + ttl
    tree["captured_at"] = captured_at.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    tree["expires_at"] = (
        datetime.fromtimestamp(expires_at, UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    tree["ref_ttl_seconds"] = ttl
    return tree


def tree_expired(expires_at: str) -> bool:
    return datetime.now(UTC) >= parse_iso8601(expires_at)


def maybe_capture_action_fallback(
    serial: str,
    fallback_path: str | None,
    *,
    force: bool = False,
) -> dict[str, Any] | None:
    if not fallback_path and not force:
        return None
    screenshot = handle_screenshot(argparse.Namespace(serial=serial, path=fallback_path))
    return {"screenshot": screenshot["path"]}


def verify_tree_change(
    serial: str,
    previous_tree_id: str,
    *,
    previous_digest: str | None = None,
    previous_event_sequence: int | None = None,
    timeout_seconds: float,
    screenshot_fallback_path: str | None,
    require_change: bool,
) -> dict[str, Any]:
    deadline = time.time() + timeout_seconds
    latest_tree_id = previous_tree_id
    while time.time() < deadline:
        tree = current_ui_tree(serial)
        latest_tree_id = str(tree["tree_id"])
        digest_changed = previous_digest is not None and tree.get("digest") != previous_digest
        event_changed = (
            previous_event_sequence is not None
            and tree.get("event_sequence") != previous_event_sequence
        )
        id_changed = previous_digest is None and latest_tree_id != previous_tree_id
        if digest_changed or event_changed or id_changed:
            return {
                "changed": True,
                "tree_id": latest_tree_id,
                "digest": tree.get("digest"),
                "event_sequence": tree.get("event_sequence"),
                "captured_at": tree.get("captured_at"),
                "expires_at": tree.get("expires_at"),
            }
        time.sleep(0.35)
    fallback = maybe_capture_action_fallback(
        serial,
        screenshot_fallback_path,
        force=True,
    )
    if require_change:
        detail = ""
        if fallback:
            detail = f"; screenshot fallback saved to {fallback['screenshot']}"
        raise RuntimeError(f"UI tree did not change after the action{detail}")
    result: dict[str, Any] = {"changed": False, "tree_id": latest_tree_id}
    if fallback:
        result["fallback"] = fallback
    return result


def verify_coordinate_action(
    serial: str,
    before: dict[str, Any],
    args: argparse.Namespace,
) -> dict[str, Any]:
    return verify_tree_change(
        serial,
        str(before["tree_id"]),
        previous_digest=before.get("digest"),
        previous_event_sequence=before.get("event_sequence"),
        timeout_seconds=float(getattr(args, "verify_timeout", _DEFAULT_VERIFY_TIMEOUT_SECONDS)),
        screenshot_fallback_path=getattr(args, "fallback_screenshot", None),
        require_change=bool(getattr(args, "require_change", False)),
    )


def simple_adb_input_text(value: str) -> bool:
    return bool(_SIMPLE_INPUT_TEXT.fullmatch(value.strip()))


def set_clipboard_text(serial: str, text: str) -> dict[str, Any]:
    if not text:
        raise ValueError("text must not be empty")
    grpc_json(
        serial,
        "android.emulation.control.EmulatorController/setClipboard",
        {"text": text},
    )
    clipboard = grpc_json(
        serial,
        "android.emulation.control.EmulatorController/getClipboard",
        {},
    )
    if clipboard.get("text") != text:
        raise RuntimeError("emulator clipboard verification failed")
    return clipboard


def get_clipboard_text(serial: str) -> dict[str, Any]:
    return grpc_json(
        serial,
        "android.emulation.control.EmulatorController/getClipboard",
        {},
    )


def get_emulator_status(serial: str) -> dict[str, Any]:
    status = grpc_json(
        serial,
        "android.emulation.control.EmulatorController/getStatus",
        {},
    )
    vm_state = grpc_json(
        serial,
        "android.emulation.control.EmulatorController/getVmState",
        {},
    )
    return {
        "grpc_url": default_grpc_url_for_serial(serial),
        "status": status,
        "vm_state": vm_state,
    }


def set_vm_state(serial: str, state: str) -> dict[str, Any]:
    grpc_json(
        serial,
        "android.emulation.control.EmulatorController/setVmState",
        {"state": state},
    )
    return get_emulator_status(serial)


def live_view(serial: str) -> dict[str, Any]:
    adb_endpoint = serial if is_tcp_endpoint(serial) else None
    grpc_url = default_grpc_endpoint(serial)
    result: dict[str, Any] = {"serial": serial}
    if adb_endpoint:
        result["adb_endpoint"] = adb_endpoint
    if grpc_url:
        result["grpc_url"] = grpc_url
    viewer_url = default_view_endpoint(serial)
    if viewer_url:
        result["viewer_url"] = viewer_url
    companion_url = default_companion_endpoint(serial)
    if companion_url:
        result["companion_url"] = companion_url
    viewer_status = load_json_file(browser_files_root() / "android-viewer" / "status.json")
    if viewer_status:
        result["viewer_status"] = viewer_status
    return result


def health_report(serial: str) -> dict[str, Any]:
    ensure_device_connection(serial)
    entry = device_entry(serial) or {"serial": serial, "state": "unknown"}
    boot_completed = shell_text(serial, "getprop", "sys.boot_completed")
    boot_anim = shell_text(serial, "getprop", "init.svc.bootanim")
    size = parse_wm_size(shell_text(serial, "wm", "size"))
    density = shell_text(serial, "wm", "density")
    focus = parse_focus(shell_text(serial, "dumpsys", "window", timeout=180))
    report = {
        "serial": serial,
        "state": entry.get("state"),
        "boot_completed": boot_completed == "1",
        "boot_animation": boot_anim,
        "display": size,
        "density": safe_text(density) or None,
        "focus": focus,
        "live_view": live_view(serial),
    }
    grpc_url = default_grpc_endpoint(serial)
    if grpc_url:
        try:
            report["emulator"] = get_emulator_status(serial)
        except Exception as exc:
            report["emulator_error"] = safe_text(exc)
    try:
        report["accessibility"] = accessibility_request(serial, {"op": "health"}, timeout=5.0)
    except Exception as exc:
        report["accessibility_error"] = safe_text(exc)
    return report


def handle_devices(_: argparse.Namespace) -> dict[str, Any]:
    return {"devices": connected_devices()}


def handle_status(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    props = {
        "state": run_adb(serial, "get-state").strip(),
        "model": shell_text(serial, "getprop", "ro.product.model"),
        "device": shell_text(serial, "getprop", "ro.product.device"),
        "manufacturer": shell_text(serial, "getprop", "ro.product.manufacturer"),
        "android_release": shell_text(serial, "getprop", "ro.build.version.release"),
        "sdk": shell_text(serial, "getprop", "ro.build.version.sdk"),
        "boot_completed": shell_text(serial, "getprop", "sys.boot_completed") == "1",
        "display": parse_wm_size(shell_text(serial, "wm", "size")),
    }
    return {"serial": serial, "device": props}


def handle_connect(args: argparse.Namespace) -> dict[str, Any]:
    response = run_adb(None, "connect", args.endpoint).strip()
    return {"endpoint": args.endpoint, "response": response}


def handle_disconnect(args: argparse.Namespace) -> dict[str, Any]:
    serial = args.serial or ""
    response = run_adb(None, "disconnect", serial).strip()
    return {"serial": serial or None, "response": response}


def handle_screenshot(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    destination = resolve_output_path(args.path, serial, "screenshots", ".png")
    grpc_url = default_grpc_endpoint(serial)
    if grpc_url:
        try:
            screenshot = grpc_json(
                serial,
                "android.emulation.control.EmulatorController/getScreenshot",
                {"format": "PNG", "display": 0},
                timeout=120,
            )
            encoded = screenshot.get("image")
            if not isinstance(encoded, str) or not encoded:
                raise RuntimeError("emulator gRPC screenshot returned no image data")
            destination.write_bytes(base64.b64decode(encoded, validate=True))
            return {
                "serial": serial,
                "path": str(destination),
                "size_bytes": destination.stat().st_size,
                "source": "emulator-grpc",
                "secure_windows_visible": True,
            }
        except (RuntimeError, ValueError, OSError) as exc:
            grpc_error = safe_text(exc)
    else:
        grpc_error = "emulator gRPC endpoint is not configured"

    payload = run_adb(serial, "exec-out", "screencap", "-p", text=False, timeout=120)
    destination.write_bytes(bytes(payload))
    return {
        "serial": serial,
        "path": str(destination),
        "size_bytes": destination.stat().st_size,
        "source": "adb-screencap",
        "secure_windows_visible": False,
        "grpc_error": grpc_error,
    }


def handle_record(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    destination = resolve_output_path(args.path, serial, "recordings", ".mp4")
    remaining = args.seconds
    remote_names: list[str] = []
    try:
        with tempfile.TemporaryDirectory(prefix="android-record-", dir=destination.parent) as raw_temp:
            temp_dir = Path(raw_temp)
            parts: list[Path] = []
            while remaining > 0:
                duration = min(remaining, 170)
                remote_name = f"/sdcard/Download/hermes-record-{uuid.uuid4().hex[:12]}.mp4"
                remote_names.append(remote_name)
                part = temp_dir / f"part-{len(parts):04d}.mp4"
                run_adb(
                    serial,
                    "shell",
                    "screenrecord",
                    "--time-limit",
                    str(duration),
                    remote_name,
                    timeout=duration + 30,
                )
                run_adb(serial, "pull", remote_name, str(part), timeout=duration + 30)
                run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
                remote_names.remove(remote_name)
                parts.append(part)
                remaining -= duration

            if len(parts) == 1:
                parts[0].replace(destination)
            else:
                manifest = temp_dir / "concat.txt"
                manifest.write_text(
                    "".join(f"file '{part.name}'\n" for part in parts),
                    encoding="utf-8",
                )
                completed = subprocess.run(
                    [
                        "ffmpeg",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-f",
                        "concat",
                        "-safe",
                        "0",
                        "-i",
                        str(manifest),
                        "-c",
                        "copy",
                        "-y",
                        str(destination),
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=args.seconds + 120,
                    cwd=temp_dir,
                )
                if completed.returncode != 0:
                    raise RuntimeError(f"ffmpeg failed to join recording: {safe_text(completed.stderr)}")
    finally:
        for remote_name in remote_names:
            run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
    return {
        "serial": serial,
        "duration_seconds": args.seconds,
        "path": str(destination),
        "size_bytes": destination.stat().st_size,
    }


def handle_ui_dump(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    destination = resolve_output_path(args.path, serial, "uiautomator", ".xml")
    remote_name = f"/sdcard/Download/hermes-ui-{uuid.uuid4().hex[:12]}.xml"
    run_adb(serial, "shell", "uiautomator", "dump", "--compressed", remote_name)
    try:
        run_adb(serial, "pull", remote_name, str(destination))
    finally:
        run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
    return {"serial": serial, "path": str(destination), "size_bytes": destination.stat().st_size}


def current_uiautomator_tree(serial: str) -> dict[str, Any]:
    remote_name = f"/sdcard/Download/hermes-ui-{uuid.uuid4().hex[:12]}.xml"
    run_adb(serial, "shell", "uiautomator", "dump", "--compressed", remote_name)
    try:
        xml = str(run_adb(serial, "exec-out", "cat", remote_name))
    finally:
        run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
    tree = parse_ui_tree(xml)
    tree["tree_id"] = f"uiautomator:{tree['tree_id']}"
    tree["serial"] = serial
    tree["backend"] = "uiautomator"
    return stamp_tree(tree)


def current_ui_tree(serial: str) -> dict[str, Any]:
    try:
        return accessibility_snapshot(serial)
    except Exception as exc:
        tree = current_uiautomator_tree(serial)
        tree["accessibility_error"] = safe_text(exc)
        return tree


def handle_ui_tree(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    return current_ui_tree(serial)


def compact_ui_tree_nodes(tree: dict[str, Any]) -> list[dict[str, Any]]:
    tree_id = tree.get("tree_id")
    expires_at = tree.get("expires_at")
    result: list[dict[str, Any]] = []
    for node in tree.get("nodes", []):
        if not node.get("clickable"):
            continue
        text = str(node.get("text") or "").strip()
        content_description = str(
            node.get("content_description") or node.get("description") or ""
        ).strip()
        if not text and not content_description:
            continue
        result.append(
            {
                "ref": node.get("ref"),
                "text": text,
                "content_description": content_description,
                "tree_id": tree_id,
                "expires_at": expires_at,
            }
        )
    return result


def handle_tap(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    before = current_ui_tree(serial)
    try:
        gesture = accessibility_gesture(
            serial,
            {"type": "tap", "x": args.x, "y": args.y, "duration_ms": 1},
        )
        if gesture.get("accepted"):
            return {
                "serial": serial,
                "tap": {"x": args.x, "y": args.y},
                "mode": "accessibility-gesture",
                "verification": verify_coordinate_action(serial, before, args),
            }
    except Exception:
        pass
    run_adb(serial, "shell", "input", "tap", str(args.x), str(args.y))
    return {
        "serial": serial,
        "tap": {"x": args.x, "y": args.y},
        "mode": "adb-input",
        "verification": verify_coordinate_action(serial, before, args),
    }


def handle_tap_ref(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    if args.expires_at and tree_expired(args.expires_at):
        raise RuntimeError(
            f"UI ref expired at {args.expires_at}; inspect ui-tree again before acting on {args.ref}"
        )

    tree: dict[str, Any] | None = None
    tree_id = args.tree_id
    if not tree_id:
        tree = current_ui_tree(serial)
        tree_id = str(tree["tree_id"])
    elif tree_id.startswith("uiautomator:"):
        tree = current_uiautomator_tree(serial)
    if (tree is None or tree.get("backend") == "accessibility-service") and not tree_id.startswith(
        "uiautomator:"
    ):
        try:
            action = accessibility_action(
                serial,
                tree_id,
                args.ref,
                "click",
                verify_timeout=args.verify_timeout,
                require_change=args.require_change,
            )
            result: dict[str, Any] = {
                "serial": serial,
                "tree_id": tree_id,
                "ref": args.ref,
                "mode": "accessibility-action",
                "verification": action,
            }
            if not action.get("changed"):
                result["fallback"] = maybe_capture_action_fallback(
                    serial,
                    args.fallback_screenshot,
                    force=True,
                )
            return result
        except Exception as exc:
            if args.tree_id:
                try:
                    fallback = maybe_capture_action_fallback(
                        serial,
                        args.fallback_screenshot,
                        force=True,
                    )
                except Exception:
                    fallback = None
                detail = f"; screenshot saved to {fallback['screenshot']}" if fallback else ""
                raise RuntimeError(f"{safe_text(exc)}{detail}") from exc
            if tree is not None and tree.get("backend") == "accessibility-service":
                try:
                    fallback = maybe_capture_action_fallback(
                        serial,
                        args.fallback_screenshot,
                        force=True,
                    )
                except Exception:
                    fallback = None
                detail = f"; screenshot saved to {fallback['screenshot']}" if fallback else ""
                raise RuntimeError(f"{safe_text(exc)}{detail}") from exc

    if tree is None:
        tree = current_uiautomator_tree(serial)
    if tree_id != tree["tree_id"]:
        raise RuntimeError(
            f"UI changed: expected tree {tree_id}, current tree is {tree['tree_id']}; inspect ui-tree again"
        )
    match = next((node for node in tree["nodes"] if node["ref"] == args.ref), None)
    if match is None:
        raise ValueError(f"UI ref does not exist in the current tree: {args.ref}")
    x, y = match["bounds"]["center"]
    run_adb(serial, "shell", "input", "tap", str(x), str(y))
    verification = verify_tree_change(
        serial,
        tree["tree_id"],
        timeout_seconds=args.verify_timeout,
        screenshot_fallback_path=args.fallback_screenshot,
        require_change=args.require_change,
    )
    return {
        "serial": serial,
        "tree_id": tree["tree_id"],
        "expires_at": tree.get("expires_at"),
        "ref": args.ref,
        "tap": {"x": x, "y": y},
        "node": match,
        "mode": "uiautomator-adb-fallback",
        "verification": verification,
    }


def handle_swipe(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    before = current_ui_tree(serial)
    try:
        gesture = accessibility_gesture(
            serial,
            {
                "type": "swipe",
                "x1": args.x1,
                "y1": args.y1,
                "x2": args.x2,
                "y2": args.y2,
                "duration_ms": args.duration_ms,
            },
        )
        if gesture.get("accepted"):
            return {
                "serial": serial,
                "swipe": {
                    "from": [args.x1, args.y1],
                    "to": [args.x2, args.y2],
                    "duration_ms": args.duration_ms,
                },
                "mode": "accessibility-gesture",
                "verification": verify_coordinate_action(serial, before, args),
            }
    except Exception:
        pass
    run_adb(
        serial,
        "shell",
        "input",
        "swipe",
        str(args.x1),
        str(args.y1),
        str(args.x2),
        str(args.y2),
        str(args.duration_ms),
    )
    return {
        "serial": serial,
        "swipe": {
            "from": [args.x1, args.y1],
            "to": [args.x2, args.y2],
            "duration_ms": args.duration_ms,
        },
        "mode": "adb-input",
        "verification": verify_coordinate_action(serial, before, args),
    }


def handle_long_press(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    before = current_ui_tree(serial)
    try:
        gesture = accessibility_gesture(
            serial,
            {
                "type": "long_press",
                "x": args.x,
                "y": args.y,
                "duration_ms": args.duration_ms,
            },
        )
        if gesture.get("accepted"):
            return {
                "serial": serial,
                "long_press": {"x": args.x, "y": args.y, "duration_ms": args.duration_ms},
                "mode": "accessibility-gesture",
                "verification": verify_coordinate_action(serial, before, args),
            }
    except Exception:
        pass
    run_adb(
        serial,
        "shell",
        "input",
        "swipe",
        str(args.x),
        str(args.y),
        str(args.x),
        str(args.y),
        str(args.duration_ms),
    )
    return {
        "serial": serial,
        "long_press": {"x": args.x, "y": args.y, "duration_ms": args.duration_ms},
        "mode": "adb-input",
        "verification": verify_coordinate_action(serial, before, args),
    }


def handle_text(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    accessibility_error: str | None = None
    try:
        target_ref = getattr(args, "ref", None)
        requested_tree_id = getattr(args, "tree_id", None)
        if target_ref and requested_tree_id:
            action = accessibility_action(
                serial,
                requested_tree_id,
                target_ref,
                "set_text",
                value=args.text,
                verify_timeout=args.verify_timeout,
                require_change=False,
            )
            return {
                "serial": serial,
                "text": args.text,
                "ref": target_ref,
                "mode": "accessibility-set-text",
                "verification": action,
            }
        tree = accessibility_snapshot(serial)
        if not target_ref:
            editable = [node for node in tree["nodes"] if node.get("editable")]
            target = next((node for node in editable if node.get("focused")), None)
            if target is None and len(editable) == 1:
                target = editable[0]
            if target:
                target_ref = str(target["ref"])
        if target_ref:
            action = accessibility_action(
                serial,
                str(tree["tree_id"]),
                target_ref,
                "set_text",
                value=args.text,
                verify_timeout=args.verify_timeout,
                require_change=False,
            )
            return {
                "serial": serial,
                "text": args.text,
                "ref": target_ref,
                "mode": "accessibility-set-text",
                "verification": action,
            }
    except Exception as exc:
        accessibility_error = safe_text(exc)

    try:
        clipboard = set_clipboard_text(serial, args.text)
        run_adb(serial, "shell", "input", "keyevent", "279")
        return {
            "serial": serial,
            "text": args.text,
            "mode": "grpc-clipboard-paste",
            "clipboard": clipboard,
            "accessibility_error": accessibility_error,
        }
    except Exception as clipboard_exc:
        if not simple_adb_input_text(args.text):
            raise RuntimeError(
                "Unicode text entry failed through accessibility and emulator clipboard: "
                f"{accessibility_error}; {safe_text(clipboard_exc)}"
            ) from clipboard_exc

    if simple_adb_input_text(args.text):
        encoded = encode_input_text(args.text)
        run_adb(serial, "shell", "input", "text", encoded)
        return {
            "serial": serial,
            "text": encoded,
            "mode": "adb-input-fallback",
            "accessibility_error": accessibility_error,
        }
    raise RuntimeError("text entry failed")


def handle_action_ref(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    tree_id = args.tree_id
    if not tree_id:
        tree_id = str(accessibility_snapshot(serial)["tree_id"])
    try:
        action = accessibility_action(
            serial,
            tree_id,
            args.ref,
            args.action,
            value=args.value,
            verify_timeout=args.verify_timeout,
            require_change=args.require_change,
        )
    except Exception as exc:
        try:
            fallback = maybe_capture_action_fallback(
                serial,
                args.fallback_screenshot,
                force=True,
            )
        except Exception:
            fallback = None
        detail = f"; screenshot saved to {fallback['screenshot']}" if fallback else ""
        raise RuntimeError(f"{safe_text(exc)}{detail}") from exc
    result: dict[str, Any] = {
        "serial": serial,
        "tree_id": tree_id,
        "ref": args.ref,
        "action": args.action,
        "verification": action,
    }
    if not action.get("changed"):
        result["fallback"] = maybe_capture_action_fallback(
            serial,
            args.fallback_screenshot,
            force=True,
        )
    return result


def handle_global_action(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    response = accessibility_request(
        serial,
        {"op": "global_action", "action": args.action},
    )
    return {"serial": serial, "global_action": response}


def handle_keyevent(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    run_adb(serial, "shell", "input", "keyevent", str(args.keyevent))
    return {"serial": serial, "keyevent": str(args.keyevent)}


def handle_open_url(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    run_adb(
        serial,
        "shell",
        "am",
        "start",
        "-a",
        "android.intent.action.VIEW",
        "-d",
        args.url,
    )
    return {"serial": serial, "url": args.url}


def handle_app_start(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    if args.activity:
        target = f"{args.package}/{args.activity}"
        run_adb(serial, "shell", "am", "start", "-n", target)
    else:
        run_adb(
            serial,
            "shell",
            "monkey",
            "-p",
            args.package,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        )
    return {
        "serial": serial,
        "package": args.package,
        "activity": args.activity,
    }


def handle_app_stop(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    run_adb(serial, "shell", "am", "force-stop", args.package)
    return {"serial": serial, "package": args.package}


def handle_install(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    source = resolve_local_source(args.path)
    command = ["install"]
    if args.replace:
        command.append("-r")
    if args.grant_all:
        command.append("-g")
    if args.downgrade:
        command.append("-d")
    if args.test_only:
        command.append("-t")
    command.append(str(source))
    response = str(run_adb(serial, *command, timeout=args.timeout)).strip()
    return {"serial": serial, "path": str(source), "response": response}


def handle_install_aurora(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    source = resolve_local_source(
        os.environ.get("AURORA_STORE_APK", str(_AURORA_STORE_APK))
    )
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != _AURORA_STORE_SHA256:
        raise RuntimeError(
            f"Aurora Store APK checksum mismatch: expected {_AURORA_STORE_SHA256}, got {digest}"
        )
    response = str(
        run_adb(serial, "install", "-r", "-g", str(source), timeout=args.timeout)
    ).strip()
    package_path = shell_text(
        serial,
        "pm",
        "path",
        _AURORA_STORE_PACKAGE,
        timeout=args.timeout,
    )
    if not package_path.startswith("package:"):
        raise RuntimeError(
            f"Aurora Store installation did not expose {_AURORA_STORE_PACKAGE}: {package_path}"
        )
    return {
        "serial": serial,
        "package": _AURORA_STORE_PACKAGE,
        "version": _AURORA_STORE_VERSION,
        "path": str(source),
        "sha256": digest,
        "response": response,
        "package_path": package_path,
    }


def handle_uninstall(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    command = ["uninstall"]
    if args.keep_data:
        command.append("-k")
    command.append(args.package)
    response = str(run_adb(serial, *command, timeout=args.timeout)).strip()
    return {"serial": serial, "package": args.package, "response": response}


def handle_packages(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    command = ["pm", "list", "packages"]
    if args.third_party:
        command.append("-3")
    if args.system:
        command.append("-s")
    if args.filter:
        command.append(args.filter)
    output = shell_text(serial, *command, timeout=180)
    packages = sorted(
        line.removeprefix("package:").strip()
        for line in output.splitlines()
        if line.strip().startswith("package:")
    )
    return {"serial": serial, "packages": packages, "count": len(packages)}


def handle_permission(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    run_adb(serial, "shell", "pm", args.action, args.package, args.permission)
    return {
        "serial": serial,
        "action": args.action,
        "package": args.package,
        "permission": args.permission,
    }


def handle_rotate(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    if args.orientation == "auto":
        run_adb(serial, "shell", "settings", "put", "system", "accelerometer_rotation", "1")
    else:
        rotations = {
            "portrait": "0",
            "landscape": "1",
            "reverse-portrait": "2",
            "reverse-landscape": "3",
        }
        run_adb(serial, "shell", "settings", "put", "system", "accelerometer_rotation", "0")
        run_adb(
            serial,
            "shell",
            "settings",
            "put",
            "system",
            "user_rotation",
            rotations[args.orientation],
        )
    return {"serial": serial, "orientation": args.orientation}


def handle_pull(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    destination = resolve_output_path(args.path, serial, "pulls", Path(args.remote).suffix or ".bin")
    run_adb(serial, "pull", args.remote, str(destination), timeout=300)
    return {"serial": serial, "remote": args.remote, "path": str(destination)}


def handle_push(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    source = resolve_local_source(args.path)
    run_adb(serial, "push", str(source), args.remote, timeout=300)
    return {"serial": serial, "path": str(source), "remote": args.remote}


def handle_wait_for_boot(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    deadline = time.time() + args.timeout
    last_state = "unknown"
    while time.time() < deadline:
        entry = device_entry(serial)
        last_state = str(entry.get("state")) if entry else "missing"
        if last_state == "device" and shell_text(serial, "getprop", "sys.boot_completed") == "1":
            return {"serial": serial, "boot_completed": True, "health": health_report(serial)}
        time.sleep(args.interval)
    raise RuntimeError(f"{serial} did not finish booting within {args.timeout} seconds (state={last_state})")


def handle_health(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    return health_report(serial)


def handle_snapshot(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    slug = args.name or uuid.uuid4().hex[:12]
    base = device_directory(serial, "snapshots") / safe_device_name(slug)
    base.parent.mkdir(parents=True, exist_ok=True)
    screenshot_path = Path(f"{base}.png").expanduser().resolve()
    ui_dump_path = Path(f"{base}.xml").expanduser().resolve()
    metadata_path = Path(f"{base}.json").expanduser().resolve()
    screenshot = handle_screenshot(argparse.Namespace(serial=serial, path=str(screenshot_path)))
    ui_dump = handle_ui_dump(argparse.Namespace(serial=serial, path=str(ui_dump_path)))
    health = health_report(serial)
    snapshot = {
        "name": safe_device_name(slug),
        "saved_at": iso_now(),
        "serial": serial,
        "screenshot": screenshot["path"],
        "ui_dump": ui_dump["path"],
        "health": health,
    }
    metadata_path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {
        "serial": serial,
        "snapshot": snapshot,
        "metadata_path": str(metadata_path),
    }


def handle_live_view(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    return live_view(serial)


def handle_emulator_status(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    return {"serial": serial, "emulator": get_emulator_status(serial)}


def handle_vm_state(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    if args.state:
        return {"serial": serial, "emulator": set_vm_state(serial, args.state)}
    return {"serial": serial, "emulator": get_emulator_status(serial)}


def handle_clipboard(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    return {"serial": serial, "clipboard": get_clipboard_text(serial)}


def handle_set_clipboard(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    return {"serial": serial, "clipboard": set_clipboard_text(serial, args.text)}


def handle_logcat(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    destination = resolve_output_path(args.path, serial, "logcat", ".txt")
    output = str(
        run_adb(
            serial,
            "logcat",
            "-d",
            "-t",
            str(args.lines),
            timeout=180,
        )
    )
    destination.write_text(output, encoding="utf-8")
    return {"serial": serial, "path": str(destination), "lines": args.lines}


HANDLERS = {
    "devices": handle_devices,
    "status": handle_status,
    "connect": handle_connect,
    "disconnect": handle_disconnect,
    "screenshot": handle_screenshot,
    "record": handle_record,
    "uiautomator-dump": handle_ui_dump,
    "ui-tree": handle_ui_tree,
    "tap": handle_tap,
    "tap-ref": handle_tap_ref,
    "swipe": handle_swipe,
    "long-press": handle_long_press,
    "text": handle_text,
    "action-ref": handle_action_ref,
    "global-action": handle_global_action,
    "keyevent": handle_keyevent,
    "open-url": handle_open_url,
    "app-start": handle_app_start,
    "app-stop": handle_app_stop,
    "install": handle_install,
    "install-aurora": handle_install_aurora,
    "uninstall": handle_uninstall,
    "packages": handle_packages,
    "permission": handle_permission,
    "rotate": handle_rotate,
    "pull": handle_pull,
    "push": handle_push,
    "wait-for-boot": handle_wait_for_boot,
    "health": handle_health,
    "snapshot": handle_snapshot,
    "live-view": handle_live_view,
    "emulator-status": handle_emulator_status,
    "vm-state": handle_vm_state,
    "clipboard": handle_clipboard,
    "set-clipboard": handle_set_clipboard,
    "logcat": handle_logcat,
}


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="android",
        description="Operate Android devices with structured helpers or unrestricted adb passthrough.",
    )
    root.add_argument("--serial", help="adb device serial; defaults to ANDROID_SERIAL")
    sub = root.add_subparsers(dest="command", required=True)

    sub.add_parser("devices", help="list adb-visible devices with metadata")
    sub.add_parser("status", help="show one device's basic identity and Android version")
    health = sub.add_parser("health", help="show boot, display, focus, and live-view details")
    health.add_argument("--serial", default=argparse.SUPPRESS, help=argparse.SUPPRESS)

    connect = sub.add_parser("connect", help="connect to an adb TCP endpoint")
    connect.add_argument("endpoint", help="host:port or serial endpoint for adb connect")

    sub.add_parser("disconnect", help="disconnect adb from --serial or all devices")

    screenshot = sub.add_parser("screenshot", help="capture a PNG screenshot")
    screenshot.add_argument(
        "path",
        nargs="?",
        help="optional output path anywhere visible to the agent process",
    )

    record = sub.add_parser("record", help="capture an MP4 screen recording of any duration")
    record.add_argument("--seconds", type=positive_int, default=30)
    record.add_argument(
        "path",
        nargs="?",
        help="optional output path anywhere visible to the agent process",
    )

    ui_dump = sub.add_parser("uiautomator-dump", help="dump the current UI hierarchy as XML")
    ui_dump.add_argument(
        "path",
        nargs="?",
        help="optional output path anywhere visible to the agent process",
    )

    ui_tree = sub.add_parser("ui-tree", help="return a UI tree with short-lived refs")
    ui_tree.add_argument(
        "--compact",
        action="store_true",
        help="emit one JSON line per labeled clickable node",
    )

    snapshot = sub.add_parser("snapshot", help="capture screenshot, UI XML, and health in one bundle")
    snapshot.add_argument("--name", help="optional stable basename for the snapshot bundle")

    wait_for_boot = sub.add_parser("wait-for-boot", help="block until one device finishes booting")
    wait_for_boot.add_argument("--timeout", type=positive_int, default=300)
    wait_for_boot.add_argument("--interval", type=positive_float, default=2.0)

    live_view_cmd = sub.add_parser("live-view", help="show adb, browser viewer, and emulator gRPC endpoints")
    live_view_cmd.add_argument("--serial", default=argparse.SUPPRESS, help=argparse.SUPPRESS)

    sub.add_parser("emulator-status", help="show emulator gRPC status and VM state")

    vm_state = sub.add_parser("vm-state", help="get or set the emulator VM run state")
    vm_state.add_argument(
        "state",
        nargs="?",
        choices=("RUNNING", "PAUSED", "SHUTDOWN", "RESET", "RESTART", "START", "STOP"),
    )

    sub.add_parser("clipboard", help="read the emulator clipboard through gRPC")

    set_clipboard = sub.add_parser("set-clipboard", help="set the emulator clipboard through gRPC")
    set_clipboard.add_argument("text")

    tap = sub.add_parser("tap", help="tap one screen coordinate")
    tap.add_argument("x", type=int)
    tap.add_argument("y", type=int)
    tap.add_argument("--verify-timeout", type=positive_float, default=_DEFAULT_VERIFY_TIMEOUT_SECONDS)
    tap.add_argument("--fallback-screenshot")
    tap.add_argument("--require-change", action="store_true")

    tap_ref = sub.add_parser("tap-ref", help="tap the center of a ref from ui-tree")
    tap_ref.add_argument("ref", help="short-lived ref such as r12")
    tap_ref.add_argument("--tree-id", help="refuse the tap if the UI changed since ui-tree")
    tap_ref.add_argument("--expires-at", help="refuse the tap if the ref has expired")
    tap_ref.add_argument("--verify-timeout", type=positive_float, default=_DEFAULT_VERIFY_TIMEOUT_SECONDS)
    tap_ref.add_argument("--fallback-screenshot", help="save a screenshot if verification cannot confirm a change")
    tap_ref.add_argument("--require-change", action="store_true")

    swipe = sub.add_parser("swipe", help="swipe between two screen coordinates")
    swipe.add_argument("x1", type=int)
    swipe.add_argument("y1", type=int)
    swipe.add_argument("x2", type=int)
    swipe.add_argument("y2", type=int)
    swipe.add_argument("--duration-ms", type=positive_int, default=300)
    swipe.add_argument("--verify-timeout", type=positive_float, default=_DEFAULT_VERIFY_TIMEOUT_SECONDS)
    swipe.add_argument("--fallback-screenshot")
    swipe.add_argument("--require-change", action="store_true")

    long_press = sub.add_parser("long-press", help="press and hold one screen coordinate")
    long_press.add_argument("x", type=int)
    long_press.add_argument("y", type=int)
    long_press.add_argument("--duration-ms", type=positive_int, default=1000)
    long_press.add_argument("--verify-timeout", type=positive_float, default=_DEFAULT_VERIFY_TIMEOUT_SECONDS)
    long_press.add_argument("--fallback-screenshot")
    long_press.add_argument("--require-change", action="store_true")

    text = sub.add_parser("text", help="type text through adb input or emulator clipboard paste")
    text.add_argument("text")
    text.add_argument("--ref", help="editable accessibility ref to target")
    text.add_argument("--tree-id", help="tree that owns --ref")
    text.add_argument("--verify-timeout", type=positive_float, default=0.0)
    text.add_argument("--fallback-screenshot", help="save a screenshot if verification cannot confirm a change")

    action_ref = sub.add_parser("action-ref", help="perform a semantic accessibility action on a ref")
    action_ref.add_argument("ref")
    action_ref.add_argument(
        "action",
        choices=(
            "click",
            "long_click",
            "focus",
            "accessibility_focus",
            "clear_focus",
            "scroll_forward",
            "scroll_backward",
            "set_text",
        ),
    )
    action_ref.add_argument("--tree-id")
    action_ref.add_argument("--value", help="value for set_text")
    action_ref.add_argument("--verify-timeout", type=positive_float, default=_DEFAULT_VERIFY_TIMEOUT_SECONDS)
    action_ref.add_argument("--fallback-screenshot")
    action_ref.add_argument("--require-change", action="store_true")

    global_action = sub.add_parser("global-action", help="perform one Android accessibility global action")
    global_action.add_argument(
        "action",
        choices=(
            "back",
            "home",
            "recents",
            "notifications",
            "quick_settings",
            "power_dialog",
            "lock_screen",
            "take_screenshot",
        ),
    )

    keyevent = sub.add_parser("keyevent", help="send one Android keyevent")
    keyevent.add_argument("keyevent")

    open_url = sub.add_parser("open-url", help="open a URL with ACTION_VIEW")
    open_url.add_argument("url")

    app_start = sub.add_parser("app-start", help="launch one Android app")
    app_start.add_argument("package")
    app_start.add_argument("--activity", help="optional fully qualified activity name")

    app_stop = sub.add_parser("app-stop", help="force-stop one Android app")
    app_stop.add_argument("package")

    install = sub.add_parser("install", help="install an APK from Hermes-managed storage")
    install.add_argument("path")
    install.add_argument("--no-replace", action="store_false", dest="replace")
    install.add_argument("--grant-all", action="store_true")
    install.add_argument("--downgrade", action="store_true")
    install.add_argument("--test-only", action="store_true")
    install.add_argument("--timeout", type=positive_int, default=600)

    install_aurora = sub.add_parser(
        "install-aurora",
        help="verify and install the bundled Aurora Store APK",
    )
    install_aurora.add_argument("--timeout", type=positive_int, default=600)

    uninstall = sub.add_parser("uninstall", help="uninstall an Android package")
    uninstall.add_argument("package")
    uninstall.add_argument("--keep-data", action="store_true")
    uninstall.add_argument("--timeout", type=positive_int, default=300)

    packages = sub.add_parser("packages", help="list installed Android packages")
    package_kind = packages.add_mutually_exclusive_group()
    package_kind.add_argument("--third-party", action="store_true")
    package_kind.add_argument("--system", action="store_true")
    packages.add_argument("--filter")

    permission = sub.add_parser("permission", help="grant or revoke an app runtime permission")
    permission.add_argument("action", choices=("grant", "revoke"))
    permission.add_argument("package")
    permission.add_argument("permission")

    rotate = sub.add_parser("rotate", help="set or restore automatic device rotation")
    rotate.add_argument(
        "orientation",
        choices=("auto", "portrait", "landscape", "reverse-portrait", "reverse-landscape"),
    )

    pull = sub.add_parser("pull", help="pull one device file into Hermes storage")
    pull.add_argument("remote", help="remote device path")
    pull.add_argument(
        "path",
        nargs="?",
        help="optional local output path anywhere visible to the agent process",
    )

    push = sub.add_parser("push", help="push one local file onto the device")
    push.add_argument("path", help="local file anywhere visible to the agent process")
    push.add_argument("remote", help="remote destination path")

    logcat = sub.add_parser("logcat", help="save recent logcat output to Hermes storage")
    logcat.add_argument("--lines", type=positive_int, default=400)
    logcat.add_argument(
        "path",
        nargs="?",
        help="optional local output path anywhere visible to the agent process",
    )

    adb = sub.add_parser(
        "adb",
        help="run any adb command with inherited stdin/stdout/stderr and exit status",
    )
    adb.add_argument(
        "--no-serial",
        action="store_true",
        help="do not inject --serial/ANDROID_SERIAL before this global adb command",
    )
    adb.add_argument("arguments", nargs=argparse.REMAINDER)

    return root


def main() -> int:
    args = parser().parse_args()
    if args.command == "adb":
        arguments = args.arguments
        if arguments and arguments[0] == "--":
            arguments = arguments[1:]
        if not arguments:
            print("android: adb requires a command", file=sys.stderr)
            return 2
        try:
            serial = None if args.no_serial else chosen_serial(args)
            return subprocess.call(adb_command(serial, *arguments))
        except OSError as exc:
            print(f"android: unable to run adb: {safe_text(exc)}", file=sys.stderr)
            return 1
    try:
        result = HANDLERS[args.command](args)
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"android: {safe_text(exc)}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(
            f"android: request failed: {type(exc).__name__}: {safe_text(exc)}",
            file=sys.stderr,
        )
        return 1
    if args.command == "ui-tree" and args.compact:
        for node in compact_ui_tree_nodes(result):
            compact(node)
        return 0
    compact({"ok": True, **result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
