#!/usr/bin/env python3
import json
import os
import pathlib
import ssl
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime

TOKEN = pathlib.Path("/var/run/secrets/kubernetes.io/serviceaccount/token").read_text()
CA_CERT = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
API = "https://{}:{}".format(
    os.environ["KUBERNETES_SERVICE_HOST"],
    os.environ.get("KUBERNETES_SERVICE_PORT_HTTPS", "443"),
)
SSL_CONTEXT = ssl.create_default_context(cafile=CA_CERT)


def now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = None
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/merge-patch+json"
    req = urllib.request.Request(
        API + path,
        data=data,
        headers=headers,
        method=method,
    )
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=30) as res:
                payload = res.read().decode()
                return json.loads(payload) if payload else {}
        except urllib.error.HTTPError as exc:
            payload = exc.read().decode()
            raise RuntimeError(f"{method} {path} failed: {exc.code} {payload}") from exc
        except urllib.error.URLError:
            if attempt == 5:
                raise
            time.sleep(5 * attempt)
    raise RuntimeError(f"{method} {path} failed unexpectedly")


def source_path(namespace: str, source: str) -> str:
    return (
        "/apis/volsync.backube/v1alpha1/namespaces/"
        f"{namespace}/replicationsources/{source}"
    )


def trigger_source(namespace: str, source: str, token: str) -> None:
    request(
        "PATCH",
        source_path(namespace, source),
        {"spec": {"trigger": {"manual": token}}},
    )


def wait_source(namespace: str, source: str, token: str) -> None:
    deadline = time.monotonic() + int(
        os.environ.get("VOLSYNC_TIMEOUT_SECONDS", "43200")
    )
    while time.monotonic() < deadline:
        obj = request("GET", source_path(namespace, source))
        current = obj.get("spec", {}).get("trigger", {}).get("manual")
        if current != token:
            trigger_source(namespace, source, token)
        if obj.get("status", {}).get("lastManualSync") == token:
            print(f"{namespace}/{source}: manual sync complete")
            return
        time.sleep(15)
    raise TimeoutError(f"timed out waiting for {namespace}/{source} manual sync")


def main() -> int:
    namespace = os.environ["VOLSYNC_NAMESPACE"]
    source = os.environ["VOLSYNC_SOURCE"]
    token = now()
    print(f"{namespace}/{source}: triggering manual sync {token}")
    trigger_source(namespace, source, token)
    wait_source(namespace, source, token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
