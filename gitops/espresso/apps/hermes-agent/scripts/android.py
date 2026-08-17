#!/usr/bin/env python3
"""Android automation and unrestricted adb passthrough for Hermes."""

from __future__ import annotations

import argparse
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


_SAFE_NAME = re.compile(r"[^A-Za-z0-9_.-]+")
_BOUNDS = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
_AURORA_STORE_VERSION = "4.8.4"
_AURORA_STORE_PACKAGE = "com.aurora.store"
_AURORA_STORE_SHA256 = "8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad"
_AURORA_STORE_APK = Path(f"/opt/android/apks/AuroraStore-{_AURORA_STORE_VERSION}.apk")


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
    focus = parse_focus(shell_text(serial, "dumpsys", "window", "windows", timeout=180))
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
    payload = run_adb(serial, "exec-out", "screencap", "-p", text=False, timeout=120)
    destination.write_bytes(bytes(payload))
    return {"serial": serial, "path": str(destination), "size_bytes": destination.stat().st_size}


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


def current_ui_tree(serial: str) -> dict[str, Any]:
    remote_name = f"/sdcard/Download/hermes-ui-{uuid.uuid4().hex[:12]}.xml"
    run_adb(serial, "shell", "uiautomator", "dump", "--compressed", remote_name)
    try:
        xml = str(run_adb(serial, "exec-out", "cat", remote_name))
    finally:
        run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
    tree = parse_ui_tree(xml)
    tree["serial"] = serial
    return tree


def handle_ui_tree(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    return current_ui_tree(serial)


def handle_tap(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    run_adb(serial, "shell", "input", "tap", str(args.x), str(args.y))
    return {"serial": serial, "tap": {"x": args.x, "y": args.y}}


def handle_tap_ref(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    tree = current_ui_tree(serial)
    if args.tree_id and args.tree_id != tree["tree_id"]:
        raise RuntimeError(
            f"UI changed: expected tree {args.tree_id}, current tree is {tree['tree_id']}; inspect ui-tree again"
        )
    match = next((node for node in tree["nodes"] if node["ref"] == args.ref), None)
    if match is None:
        raise ValueError(f"UI ref does not exist in the current tree: {args.ref}")
    x, y = match["bounds"]["center"]
    run_adb(serial, "shell", "input", "tap", str(x), str(y))
    return {
        "serial": serial,
        "tree_id": tree["tree_id"],
        "ref": args.ref,
        "tap": {"x": x, "y": y},
        "node": match,
    }


def handle_swipe(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
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
    }


def handle_long_press(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
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
    }


def handle_text(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_connected_serial(args)
    encoded = encode_input_text(args.text)
    run_adb(serial, "shell", "input", "text", encoded)
    return {"serial": serial, "text": encoded}


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
    health.add_argument("--serial", help=argparse.SUPPRESS)

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

    sub.add_parser("ui-tree", help="return a compact UI tree with short-lived coordinate refs")

    snapshot = sub.add_parser("snapshot", help="capture screenshot, UI XML, and health in one bundle")
    snapshot.add_argument("--name", help="optional stable basename for the snapshot bundle")

    wait_for_boot = sub.add_parser("wait-for-boot", help="block until one device finishes booting")
    wait_for_boot.add_argument("--timeout", type=positive_int, default=300)
    wait_for_boot.add_argument("--interval", type=positive_float, default=2.0)

    live_view_cmd = sub.add_parser("live-view", help="show adb, browser viewer, and emulator gRPC endpoints")
    live_view_cmd.add_argument("--serial", help=argparse.SUPPRESS)

    tap = sub.add_parser("tap", help="tap one screen coordinate")
    tap.add_argument("x", type=int)
    tap.add_argument("y", type=int)

    tap_ref = sub.add_parser("tap-ref", help="tap the center of a ref from ui-tree")
    tap_ref.add_argument("ref", help="short-lived ref such as r12")
    tap_ref.add_argument("--tree-id", help="refuse the tap if the UI changed since ui-tree")

    swipe = sub.add_parser("swipe", help="swipe between two screen coordinates")
    swipe.add_argument("x1", type=int)
    swipe.add_argument("y1", type=int)
    swipe.add_argument("x2", type=int)
    swipe.add_argument("y2", type=int)
    swipe.add_argument("--duration-ms", type=positive_int, default=300)

    long_press = sub.add_parser("long-press", help="press and hold one screen coordinate")
    long_press.add_argument("x", type=int)
    long_press.add_argument("y", type=int)
    long_press.add_argument("--duration-ms", type=positive_int, default=1000)

    text = sub.add_parser("text", help="type simple text through adb input")
    text.add_argument("text")

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
    compact({"ok": True, **result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
