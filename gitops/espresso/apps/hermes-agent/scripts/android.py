#!/usr/bin/env python3
"""Allowlisted Android automation CLI built on adb."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any


_SAFE_NAME = re.compile(r"[^A-Za-z0-9_.-]+")


def compact(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def safe_text(value: Any) -> str:
    return str(value).strip()[:500]


def safe_device_name(value: str) -> str:
    return _SAFE_NAME.sub("_", value.strip())[:80] or "default"


def hermes_home() -> Path:
    return Path(os.environ.get("HERMES_HOME", "/opt/data")).resolve()


def browser_files_root() -> Path:
    return Path(os.environ.get("BROWSER_FILES_ROOT", "/opt/browser-files")).resolve()


def allowed_local_roots() -> list[Path]:
    return [
        (hermes_home() / "workspace").resolve(),
        (hermes_home() / "cache").resolve(),
        browser_files_root(),
    ]


def ensure_within_roots(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if not any(resolved.is_relative_to(root) for root in allowed_local_roots()):
        raise ValueError(
            f"local path must be under the Hermes workspace, cache, or browser files root: {path}"
        )
    return resolved


def resolve_local_source(raw_path: str) -> Path:
    source = ensure_within_roots(Path(raw_path))
    if not source.is_file() or source.is_symlink():
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
        destination = ensure_within_roots(Path(raw_path))
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
    return args.serial or os.environ.get("ANDROID_SERIAL") or None


def require_serial(args: argparse.Namespace) -> str:
    serial = chosen_serial(args)
    if not serial:
        raise ValueError("set --serial or ANDROID_SERIAL when targeting one Android device")
    return serial


def handle_devices(_: argparse.Namespace) -> dict[str, Any]:
    return {"devices": parse_devices(str(run_adb(None, "devices", "-l")))}


def handle_status(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    props = {
        "state": run_adb(serial, "get-state").strip(),
        "model": run_adb(serial, "shell", "getprop", "ro.product.model").strip(),
        "device": run_adb(serial, "shell", "getprop", "ro.product.device").strip(),
        "manufacturer": run_adb(serial, "shell", "getprop", "ro.product.manufacturer").strip(),
        "android_release": run_adb(serial, "shell", "getprop", "ro.build.version.release").strip(),
        "sdk": run_adb(serial, "shell", "getprop", "ro.build.version.sdk").strip(),
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
    serial = require_serial(args)
    destination = resolve_output_path(args.path, serial, "screenshots", ".png")
    payload = run_adb(serial, "exec-out", "screencap", "-p", text=False, timeout=120)
    destination.write_bytes(bytes(payload))
    return {"serial": serial, "path": str(destination), "size_bytes": destination.stat().st_size}


def handle_record(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    destination = resolve_output_path(args.path, serial, "recordings", ".mp4")
    remote_name = f"/sdcard/Download/hermes-record-{uuid.uuid4().hex[:12]}.mp4"
    run_adb(
        serial,
        "shell",
        "screenrecord",
        "--time-limit",
        str(args.seconds),
        remote_name,
        timeout=args.seconds + 30,
    )
    try:
        run_adb(serial, "pull", remote_name, str(destination), timeout=args.seconds + 30)
    finally:
        run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
    return {"serial": serial, "path": str(destination), "size_bytes": destination.stat().st_size}


def handle_ui_dump(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    destination = resolve_output_path(args.path, serial, "uiautomator", ".xml")
    remote_name = f"/sdcard/Download/hermes-ui-{uuid.uuid4().hex[:12]}.xml"
    run_adb(serial, "shell", "uiautomator", "dump", "--compressed", remote_name)
    try:
        run_adb(serial, "pull", remote_name, str(destination))
    finally:
        run_adb(serial, "shell", "rm", "-f", remote_name, check=False)
    return {"serial": serial, "path": str(destination), "size_bytes": destination.stat().st_size}


def handle_tap(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    run_adb(serial, "shell", "input", "tap", str(args.x), str(args.y))
    return {"serial": serial, "tap": {"x": args.x, "y": args.y}}


def handle_swipe(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
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


def handle_text(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    encoded = encode_input_text(args.text)
    run_adb(serial, "shell", "input", "text", encoded)
    return {"serial": serial, "text": encoded}


def handle_keyevent(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    run_adb(serial, "shell", "input", "keyevent", str(args.keyevent))
    return {"serial": serial, "keyevent": str(args.keyevent)}


def handle_open_url(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
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
    serial = require_serial(args)
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
    serial = require_serial(args)
    run_adb(serial, "shell", "am", "force-stop", args.package)
    return {"serial": serial, "package": args.package}


def handle_pull(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    destination = resolve_output_path(args.path, serial, "pulls", Path(args.remote).suffix or ".bin")
    run_adb(serial, "pull", args.remote, str(destination), timeout=300)
    return {"serial": serial, "remote": args.remote, "path": str(destination)}


def handle_push(args: argparse.Namespace) -> dict[str, Any]:
    serial = require_serial(args)
    source = resolve_local_source(args.path)
    run_adb(serial, "push", str(source), args.remote, timeout=300)
    return {"serial": serial, "path": str(source), "remote": args.remote}


HANDLERS = {
    "devices": handle_devices,
    "status": handle_status,
    "connect": handle_connect,
    "disconnect": handle_disconnect,
    "screenshot": handle_screenshot,
    "record": handle_record,
    "uiautomator-dump": handle_ui_dump,
    "tap": handle_tap,
    "swipe": handle_swipe,
    "text": handle_text,
    "keyevent": handle_keyevent,
    "open-url": handle_open_url,
    "app-start": handle_app_start,
    "app-stop": handle_app_stop,
    "pull": handle_pull,
    "push": handle_push,
}


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="android",
        description="Operate Android devices over adb with Hermes-safe file handling.",
    )
    root.add_argument("--serial", help="adb device serial; defaults to ANDROID_SERIAL")
    sub = root.add_subparsers(dest="command", required=True)

    sub.add_parser("devices", help="list adb-visible devices with metadata")
    sub.add_parser("status", help="show one device's basic identity and Android version")

    connect = sub.add_parser("connect", help="connect to an adb TCP endpoint")
    connect.add_argument("endpoint", help="host:port or serial endpoint for adb connect")

    sub.add_parser("disconnect", help="disconnect adb from --serial or all devices")

    screenshot = sub.add_parser("screenshot", help="capture a PNG screenshot")
    screenshot.add_argument("path", nargs="?", help="optional output path under workspace/cache/browser files")

    record = sub.add_parser("record", help="capture a short MP4 screen recording")
    record.add_argument("--seconds", type=int, choices=range(1, 181), default=30, metavar="1..180")
    record.add_argument("path", nargs="?", help="optional output path under workspace/cache/browser files")

    ui_dump = sub.add_parser("uiautomator-dump", help="dump the current UI hierarchy as XML")
    ui_dump.add_argument("path", nargs="?", help="optional output path under workspace/cache/browser files")

    tap = sub.add_parser("tap", help="tap one screen coordinate")
    tap.add_argument("x", type=int)
    tap.add_argument("y", type=int)

    swipe = sub.add_parser("swipe", help="swipe between two screen coordinates")
    swipe.add_argument("x1", type=int)
    swipe.add_argument("y1", type=int)
    swipe.add_argument("x2", type=int)
    swipe.add_argument("y2", type=int)
    swipe.add_argument("--duration-ms", type=int, choices=range(1, 60001), default=300, metavar="1..60000")

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

    pull = sub.add_parser("pull", help="pull one device file into Hermes storage")
    pull.add_argument("remote", help="remote device path")
    pull.add_argument("path", nargs="?", help="optional local output path under workspace/cache/browser files")

    push = sub.add_parser("push", help="push one local file onto the device")
    push.add_argument("path", help="local file under workspace/cache/browser files")
    push.add_argument("remote", help="remote destination path")

    return root


def main() -> int:
    args = parser().parse_args()
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
