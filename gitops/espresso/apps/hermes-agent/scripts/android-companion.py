#!/usr/bin/env python3
"""Authenticated Android companion for semantic snapshots and emulator control."""

from __future__ import annotations

import argparse
import hmac
import importlib.util
import json
import os
import signal
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
ANDROID_SCRIPT = SCRIPT_DIR / "android.py"
SPEC = importlib.util.spec_from_file_location("hermes_android", ANDROID_SCRIPT)
assert SPEC and SPEC.loader
android = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(android)


def token_value() -> str:
    token = os.environ.get("ANDROID_COMPANION_TOKEN", "").strip()
    if token:
        return token
    token_file = Path(
        os.environ.get(
            "ANDROID_COMPANION_TOKEN_FILE",
            "/opt/android/companion/auth-token",
        )
    )
    value = token_file.read_text(encoding="utf-8").strip()
    if not value:
        raise RuntimeError(f"empty companion token file: {token_file}")
    return value


def default_serial() -> str:
    serial = os.environ.get("ANDROID_SERIAL", "").strip()
    if not serial:
        raise RuntimeError("set ANDROID_SERIAL for android-companion")
    return serial


def launcher_status() -> dict[str, Any] | None:
    return android.load_json_file(Path("/opt/android/status/launcher.json"))


def accessibility_status() -> dict[str, Any] | None:
    return android.load_json_file(Path("/opt/android/status/accessibility.json"))


def metrics_payload() -> str:
    launcher = launcher_status() or {}
    accessibility = accessibility_status() or {}
    launcher_state = str(launcher.get("state", "unknown"))
    if launcher_state not in {"disabled", "running", "starting", "stopped"}:
        launcher_state = "unknown"
    accessibility_state = str(accessibility.get("state", "unknown"))
    if accessibility_state not in {"ready", "starting", "stopped"}:
        accessibility_state = "unknown"
    available = int(launcher_state == "running" and accessibility_state == "ready")
    disabled = int(launcher_state == "disabled")
    return "\n".join(
        (
            "# HELP hermes_android_companion_up Whether the Android companion HTTP service is running.",
            "# TYPE hermes_android_companion_up gauge",
            "hermes_android_companion_up 1",
            "# HELP hermes_android_available Whether Android and its accessibility service are ready for agent work.",
            "# TYPE hermes_android_available gauge",
            f"hermes_android_available {available}",
            "# HELP hermes_android_disabled Whether the launcher deliberately disabled an incompatible image.",
            "# TYPE hermes_android_disabled gauge",
            f"hermes_android_disabled {disabled}",
            "# HELP hermes_android_launcher_state Current launcher state.",
            "# TYPE hermes_android_launcher_state gauge",
            f'hermes_android_launcher_state{{state="{launcher_state}"}} 1',
            "# HELP hermes_android_accessibility_state Current accessibility companion state.",
            "# TYPE hermes_android_accessibility_state gauge",
            f'hermes_android_accessibility_state{{state="{accessibility_state}"}} 1',
            "",
        )
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "HermesAndroidCompanion/1.0"

    def log_message(self, format: str, *args: object) -> None:
        return

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(30)

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, status: int, body: str, content_type: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def require_auth(self) -> bool:
        header = self.headers.get("Authorization", "")
        expected = f"Bearer {token_value()}"
        if hmac.compare_digest(header, expected):
            return True
        self.send_json(
            HTTPStatus.UNAUTHORIZED,
            {"ok": False, "error": "missing or invalid bearer token"},
        )
        return False

    def body_json(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length < 0 or content_length > 1024 * 1024:
            raise ValueError("request body exceeds one MiB")
        if content_length == 0:
            return {}
        raw = self.rfile.read(content_length)
        parsed = json.loads(raw.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise ValueError("request body must be a JSON object")
        return parsed

    def serial_from_body(self, body: dict[str, Any]) -> str:
        serial = str(body.get("serial") or default_serial()).strip()
        if not serial:
            raise ValueError("serial is required")
        return serial

    def do_GET(self) -> None:
        try:
            if self.path == "/healthz":
                self.send_json(
                    HTTPStatus.OK,
                    {"ok": True, "service": "android-companion", "launcher": launcher_status()},
                )
                return
            if self.path == "/readyz":
                launcher = launcher_status()
                if launcher and launcher.get("state") == "disabled":
                    self.send_json(
                        HTTPStatus.OK,
                        {"ok": True, "disabled": True, "launcher": launcher},
                    )
                    return
                payload = android.health_report(default_serial())
                if not payload.get("boot_completed") or "accessibility_error" in payload:
                    self.send_json(
                        HTTPStatus.SERVICE_UNAVAILABLE,
                        {"ok": False, "launcher": launcher, **payload},
                    )
                    return
                self.send_json(HTTPStatus.OK, {"ok": True, "launcher": launcher, **payload})
                return
            if self.path == "/metrics":
                self.send_text(
                    HTTPStatus.OK,
                    metrics_payload(),
                    "text/plain; version=0.0.4; charset=utf-8",
                )
                return
            if not self.require_auth():
                return
            if self.path == "/v1/status":
                payload = android.health_report(default_serial())
                self.send_json(HTTPStatus.OK, {"ok": True, **payload})
                return
            if self.path == "/v1/ui-tree":
                payload = android.current_ui_tree(default_serial())
                self.send_json(HTTPStatus.OK, {"ok": True, **payload})
                return
            if self.path == "/v1/accessibility":
                payload = android.accessibility_request(
                    default_serial(),
                    {"op": "health"},
                )
                self.send_json(HTTPStatus.OK, {"ok": True, **payload})
                return
            if self.path == "/v1/emulator":
                payload = android.get_emulator_status(default_serial())
                self.send_json(
                    HTTPStatus.OK,
                    {"ok": True, "serial": default_serial(), "emulator": payload},
                )
                return
            if self.path == "/v1/clipboard":
                payload = android.get_clipboard_text(default_serial())
                self.send_json(
                    HTTPStatus.OK,
                    {"ok": True, "serial": default_serial(), "clipboard": payload},
                )
                return
            self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
        except Exception as exc:
            self.send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"ok": False, "error": android.safe_text(exc)},
            )

    def do_POST(self) -> None:
        if not self.require_auth():
            return
        try:
            body = self.body_json()
            serial = self.serial_from_body(body)
            if self.path == "/v1/tap-ref":
                payload = android.handle_tap_ref(
                    argparse.Namespace(
                        serial=serial,
                        ref=body["ref"],
                        tree_id=body.get("tree_id"),
                        expires_at=body.get("expires_at"),
                        verify_timeout=float(body.get("verify_timeout", 3.0)),
                        fallback_screenshot=body.get("fallback_screenshot"),
                        require_change=bool(body.get("require_change", False)),
                    )
                )
                self.send_json(HTTPStatus.OK, {"ok": True, **payload})
                return
            if self.path == "/v1/text":
                payload = android.handle_text(
                    argparse.Namespace(
                        serial=serial,
                        text=str(body["text"]),
                        verify_timeout=float(body.get("verify_timeout", 0.0)),
                        fallback_screenshot=body.get("fallback_screenshot"),
                        ref=body.get("ref"),
                        tree_id=body.get("tree_id"),
                    )
                )
                self.send_json(HTTPStatus.OK, {"ok": True, **payload})
                return
            if self.path == "/v1/action-ref":
                payload = android.accessibility_action(
                    serial,
                    str(body["tree_id"]),
                    str(body["ref"]),
                    str(body["action"]),
                    value=str(body["value"]) if "value" in body else None,
                    verify_timeout=float(body.get("verify_timeout", 3.0)),
                    require_change=bool(body.get("require_change", False)),
                )
                self.send_json(HTTPStatus.OK, {"ok": True, "serial": serial, **payload})
                return
            if self.path == "/v1/gesture":
                payload = android.accessibility_request(
                    serial,
                    {"op": "gesture", **body},
                )
                self.send_json(HTTPStatus.OK, {"ok": True, "serial": serial, **payload})
                return
            if self.path == "/v1/global-action":
                payload = android.accessibility_request(
                    serial,
                    {"op": "global_action", "action": body["action"]},
                )
                self.send_json(HTTPStatus.OK, {"ok": True, "serial": serial, **payload})
                return
            if self.path == "/v1/clipboard":
                payload = android.set_clipboard_text(serial, str(body["text"]))
                self.send_json(
                    HTTPStatus.OK,
                    {"ok": True, "serial": serial, "clipboard": payload},
                )
                return
            if self.path == "/v1/vm-state":
                payload = android.set_vm_state(serial, str(body["state"]))
                self.send_json(
                    HTTPStatus.OK,
                    {"ok": True, "serial": serial, "emulator": payload},
                )
                return
            self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
        except KeyError as exc:
            self.send_json(
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": f"missing field: {exc.args[0]}"},
            )
        except Exception as exc:
            self.send_json(
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": android.safe_text(exc)},
            )


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    listen = os.environ.get("ANDROID_COMPANION_LISTEN", "0.0.0.0:8777").strip()
    host, port = listen.rsplit(":", 1)
    server = Server((host, int(port)), Handler)

    def stop_server(_: int, __: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop_server)
    signal.signal(signal.SIGINT, stop_server)
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
